@description('The name of the API Management service instance')
param apiManagementServiceName string

@description('The name of the Blob Storage account')
param blobStorageAccountName string

@description('The name of the Logic App Standard instance')
param logicAppName string

@description('The name of the Service Bus namespace')
param serviceBusNamespaceName string

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('The name of the Application Insights instance')
param applicationInsightsName string

@description('The name of the Cosmos DB account')
param cosmosDBAccountName string

@description('The email address of the owner of the service')
@minLength(1)
param publisherEmail string = 'test@test.com'

@description('The name of the owner of the service')
@minLength(1)
param publisherName string = 'Contoso'

param location string = resourceGroup().location
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().id, location))

var apiManagementServiceTokenName = toLower('${apiManagementServiceName}-${resourceToken}')
var blobStorageAccountTokenName = toLower('${blobStorageAccountName}${resourceToken}')
var logicAppPlanTokenName = toLower('${logicAppName}-plan-${resourceToken}')
var logicAppTokenName = toLower('${logicAppName}-${resourceToken}')
var serviceBusNamespaceTokenName = toLower('${serviceBusNamespaceName}-${resourceToken}')
var logAnalyticsWorkspaceTokenName = toLower('${logAnalyticsWorkspaceName}-${resourceToken}')
var cosmosDBAccountTokenName = toLower('${cosmosDBAccountName}-${resourceToken}')

var listQueues = [ 's1-received', 's1-sub1-output', 's2-received', 's3-received' ]
var s1topicName = 's1-processed'
var listBlobContainers = [ 's1-sub1-final', 's3-final' ]
var listSubscriptionNames = [ 's1-sub1', 's1-sub2', 's1-sub3' ]

var cosmosDatabaseName = 'ais-samples-db'
var cosmosS1Sub2ContainerName = 's1-sub2-final'
var cosmosS2ContainerName = 'Employees'

//
// API Management
//
resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementServiceTokenName
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

//
// Blob Storage
//
resource blobStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: blobStorageAccountTokenName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: blobStorageAccount
  name: 'default'
}

resource symbolicname 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for name in listBlobContainers: {
  name: name
  parent: blobServices
  properties: {
  }
}]

// roles to allow the logic app to send and receive messages from the service bus

var storageBlobRoleIds = [
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // blob data contributor
]
resource storageAccountRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in storageBlobRoleIds: {
  scope: blobStorageAccount
  name: guid(logicApp.id, roleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalType: 'ServicePrincipal'
    principalId: logicApp.identity.principalId
  }
}]

//
// Logic App Standard
//

resource logicAppPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: logicAppPlanTokenName
  location: location
  kind: 'elastic'
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
    size: 'WS1'
    family: 'WS'
    capacity: 1
  }
}

resource logicApp 'Microsoft.Web/sites@2022-09-01' = {
  name: logicAppTokenName
  location: location
  kind: 'functionapp,workflowapp'
  properties: {
    serverFarmId: logicAppPlan.id
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
  resource config 'config@2022-09-01' = {
    name: 'appsettings'
    properties: {
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'node'
      WEBSITE_NODE_DEFAULT_VERSION: '~18'
      AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${blobStorageAccount.name};AccountKey=${listKeys(blobStorageAccount.id, '2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${blobStorageAccount.name};AccountKey=${listKeys(blobStorageAccount.id, '2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
      WEBSITE_CONTENTSHARE: blobStorageAccount.name
      AzureFunctionsJobHost__extensionBundle__id: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
      AzureFunctionsJobHost__extensionBundle__version: '${'[1.*,'}${' 2.0.0)'}'
      APP_KIND: 'workflowApp'
      serviceBus_fullyQualifiedNamespace: '${serviceBusNamespace.name}.servicebus.windows.net'
      AzureCosmosDB_connectionString: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
      AzureBlob_blobStorageEndpoint: blobStorageAccount.properties.primaryEndpoints.blob
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      WORKFLOWS_RESOURCE_GROUP_NAME: resourceGroup().name
      WORKFLOWS_SUBSCRIPTION_ID: subscription().id
      WORKFLOWS_LOCATION_NAME: location
      WORKFLOWS_TENANT_ID: subscription().tenantId
      WORKFLOWS_MANAGEMENT_BASE_URI: 'https://management.azure.com/'
      office365_ConnectionRuntimeUrl: office365APIConnection.properties.connectionRuntimeUrl
    }
  }
}

//
// API Connections for Logic App
// These are required for managed connectors. After deployed you will need to go the portal, select the API Connector, and authorize the connection.
//

resource office365APIConnection 'Microsoft.Web/connections@2018-07-01-preview' = {
  name: 'office365'
  location: location
  kind: 'V2'
  properties: {
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
    displayName: 'office365'
  }
}

resource office365APIConnectionAccessPolicy 'Microsoft.Web/connections/accessPolicies@2016-06-01' = {
  parent: office365APIConnection
  name: 'office365-logicapp-accesspolicy'
  location: location
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        tenantId: subscription().tenantId
        objectId: logicApp.identity.principalId
      }
    }
  }
}


//
// Service Bus
//
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: serviceBusNamespaceTokenName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {}
}

resource serviceBusQueues 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = [for name in listQueues: {
  name: name
  parent: serviceBusNamespace
  properties: {

  }
}]

resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2022-01-01-preview' = {
  name: s1topicName
  parent: serviceBusNamespace
  properties: {

  }
}

resource serviceBusTopicSubscriptions 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-01-01-preview' = [for name in listSubscriptionNames: {
  name: name
  parent: serviceBusTopic
  properties: {
  }
}]

// roles to allow the logic app to send and receive messages from the service bus

var serviceBusRoleIds = [
  '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0' // service bus data receiver
  '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39' // service bus data sender
]
resource serviceBusRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in serviceBusRoleIds: {
  scope: serviceBusNamespace
  name: guid(logicApp.id, roleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalType: 'ServicePrincipal'
    principalId: logicApp.identity.principalId
  }
}]

//
// logging and monitoring
//

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: logAnalyticsWorkspaceTokenName
  location: location
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

//
// Cosmos DB
//

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDBAccountTokenName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    disableKeyBasedMetadataWriteAccess: true
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-05-15' = {
  name: cosmosDatabaseName
  parent: cosmosDbAccount
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
    options: {
      autoscaleSettings: {
        maxThroughput: 5000
      }
    }
  }
}

resource s1sub2container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-05-15' = {
  name: cosmosS1Sub2ContainerName
  parent: database
  properties: {
    resource: {
      id: cosmosS1Sub2ContainerName
      partitionKey: {
        paths: [
          '/GT_OutboundOrders/ShipToCustomer/ClientID'
        ]
        kind: 'Hash'
      }
    }
  }
}

resource s2container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-05-15' = {
  name: cosmosS2ContainerName
  parent: database
  properties: {
    resource: {
      id: cosmosS2ContainerName
      partitionKey: {
        paths: [
          '/position'
        ]
        kind: 'Hash'
      }
    }
  }
}
