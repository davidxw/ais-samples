// https://andrewilson.co.uk/post/2024/01/standard-logic-app-apim-backend/

param apimInstanceName string
param logicAppName string

resource apimInstance 'Microsoft.ApiManagement/service@2021-01-01-preview' existing = {
  name: apimInstanceName
}

resource logicApp 'Microsoft.Web/sites@2022-09-01' existing = {
  name: logicAppName
}

var workflowName = 's1-receive'
var backend_id = 'ais-sample-logic-app'
var schema_id = 'S1-JSON-input-simple'

var workflowCallbackObject = listCallbackUrl('${logicApp.id}/hostruntime/runtime/webhooks/workflow/api/management/workflows/${workflowName}/triggers/When_a_HTTP_request_is_received', '2018-11-01')

var logicAppBackendUrl = '${split(split(workflowCallbackObject.value, '?')[0], ':443')[0]}/api'

var apiPolicy_raw = loadTextContent('./policy_all_operations.xml')
var apiPolicy_complete = replace(apiPolicy_raw, '__backend-id__', backend_id)

var operationPolicy_raw = loadTextContent('./policy_operation_httptrigger.xml')
var operationPolicy_schema = replace(operationPolicy_raw, '__schema-id__', schema_id)
var operationPolicy_wf = replace(operationPolicy_schema, '__workflow-name__', workflowName)
var operationPolicy_vers = replace(operationPolicy_wf, '__api-version__', workflowCallbackObject.queries['api-version'])
var operationPolicy_sp = replace(operationPolicy_vers, '__sp__', workflowCallbackObject.queries.sp)
var operationPolicy_sv = replace(operationPolicy_sp, '__sv__', workflowCallbackObject.queries.sv)
var operationPolicy_complete = replace(operationPolicy_sv, '__sig__', workflowCallbackObject.queries.sig)

var schema = loadTextContent('./../../logicapp-workspace/ais-sample-logicapp/Artifacts/Schemas/S1_JSON_input_SCHEMA_simple.json')

// api and policy

resource api 'Microsoft.ApiManagement/service/apis@2021-01-01-preview' = {
  name: 'api-v1'
  parent: apimInstance
  properties: {
    displayName: 'Sample API'
    subscriptionRequired: true
    path: 'sample-api'
    protocols: [
      'https'
    ]
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  name: 'policy'
  parent: api
  dependsOn: [
    logicAppBackend
  ]
  properties: {
    value: apiPolicy_complete
    format: 'xml'
  }
}

// operation and policy

resource operation 'Microsoft.ApiManagement/service/apis/operations@2021-01-01-preview' = {
  name: 's1-receive'
  parent: api
  properties: {
    displayName: workflowName
    method: 'POST'
    urlTemplate: '/${workflowName}'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
  }
  resource policy 'policies@2021-01-01-preview' = {
    name: 'policy'
    dependsOn: [
      s1Schema
    ]
    properties: {
      value: operationPolicy_complete
      format: 'xml'
    }
  }
}

// backend

resource logicAppBackend 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  name: backend_id
  parent: apimInstance
  properties: {
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    url: logicAppBackendUrl
  }
}

// schema

resource s1Schema 'Microsoft.ApiManagement/service/schemas@2023-05-01-preview' = {
  name: schema_id
  parent: apimInstance
  properties: {
    schemaType: 'JSON'
    document: {
      value: schema
    }
  }
}
