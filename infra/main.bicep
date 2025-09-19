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

@description('The name of the Key Vault name')
param keyVaultName string

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
var logicAppIdentityName = toLower('${logicAppName}-identity-${resourceToken}')
var serviceBusNamespaceTokenName = toLower('${serviceBusNamespaceName}-${resourceToken}')
var logAnalyticsWorkspaceTokenName = toLower('${logAnalyticsWorkspaceName}-${resourceToken}')
var cosmosDBAccountTokenName = toLower('${cosmosDBAccountName}-${resourceToken}')
var applicationInsightsTokenName = toLower('${applicationInsightsName}-${resourceToken}')
var keyVaultNameTokenName = toLower('${keyVaultName}-${resourceToken}')

var listQueues = ['s1-received', 's1-sub3-output', 's2-received', 's3-received']
var s1topicName = 's1-processed'
var listBlobContainers = ['s1-sub1-final', 's3-received', 's3-final']
var listSubscriptionNames = ['s1-sub1', 's1-sub2', 's1-sub3']

var cosmosDatabaseName = 'ais-samples-db'
var cosmosLogicAppTriggerLeasesContainerName = 'logic_app_trigger_leases'
var cosmosS1Sub2ContainerName = 's1-sub2-final'
var cosmosS2ContainerName = 'Employees'

var tags = {
  SecurityControl: 'Ignore'
  CostControl: 'Ignore'
}

// managed identity to assign to the logic app for accessing resources. Required to access workflow storage via managed identity and not keys
// https://review.learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal?branch=main&branchFallbackFrom=pr-en-us-279972#set-up-managed-identity-access-to-your-storage-account
// Note that the user assigned managed is only used to access the internal logic app workflow storage account. The logic app itself uses a system assigned managed identity for other resource access.
resource logicAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: logicAppIdentityName
  location: location
  tags: tags
}

//
// API Management
//
resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementServiceTokenName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

output createdLogicAppName string = logicAppTokenName
output createdApiManagementServiceName string = apiManagementServiceTokenName

//
// Blob Storage
//
resource blobStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: blobStorageAccountTokenName
  location: location
  tags: tags
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

resource symbolicname 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [
  for name in listBlobContainers: {
    name: name
    parent: blobServices
    properties: {}
  }
]

// roles to allow the logic app to use the user assigned managed identity to access the blob storage account
// https://review.learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal?branch=main&branchFallbackFrom=pr-en-us-279972#set-up-managed-identity-access-to-your-storage-account

var storageBlobRoleIdsWorkflowStorage = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // storage blob data owner
  '17d1049b-9a84-46fb-8f53-869881c3d3ab' // storage contributor
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // storage queue data contributor
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // storage table data contributor

]
resource storageAccountRbacWorkflowStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in storageBlobRoleIdsWorkflowStorage: {
    scope: blobStorageAccount
    name: guid(logicApp.id, 'workflowStorage', roleId)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalType: 'ServicePrincipal'
      principalId: logicAppIdentity.properties.principalId
    }
  }
]

// roles to allow the logic app blob connectors to read and write to blob storage
var storageBlobRoleIdsLogicAppFlows = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // storage blob data owner
]

resource storageAccountRbacLogicAppFlows 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in storageBlobRoleIdsLogicAppFlows: {
    scope: blobStorageAccount
    name: guid(logicApp.id, 'flows', roleId)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalType: 'ServicePrincipal'
      principalId: logicApp.identity.principalId
    }
  }
]


//
// A key vault to store the connection strings. The service bus and blob storage connections used by the logic app use managed
// identities for access so connection strings are not required.  The Cosmos DB connection requires a connection string however,
// as do the blob and app insights connections for the the logic app runtime.
//

// secret reader permissions for the logic app. Ideally you would scope this to the specific secrets that the logic app needs to read.
var keyVaultSecretsReaderRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)

resource kvFunctionAppPermissions 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(kv.id, logicApp.name, keyVaultSecretsReaderRole)
  scope: kv
  properties: {
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsReaderRole
  }
}

resource kv 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: keyVaultNameTokenName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: false
  }
}

// secrets:
//  CosmosDB connection string
//  Blob storage connection string
//  Application Insights connection string

resource CONNECTION_STRING_COSMOSDB 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'CONNECTION-STRING-COSMOSDB'
  parent: kv
  properties: {
    value: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
  }
}

resource CONNECTION_STRING_BLOB_STORAGE 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'CONNECTION-STRING-BLOB-STORAGE'
  parent: kv
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${blobStorageAccount.name};AccountKey=${listKeys(blobStorageAccount.id, '2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
  }
}

resource CONNECTION_STRING_APP_INSIGHTS 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'CONNECTION-STRING-APP-INSIGHTS'
  parent: kv
  properties: {
    value: applicationInsights.properties.ConnectionString
  }
}

//
// Logic App Standard
//

resource logicAppPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: logicAppPlanTokenName
  location: location
  tags: tags
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
  tags: tags
  kind: 'functionapp,workflowapp'
  properties: {
    serverFarmId: logicAppPlan.id
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${logicAppIdentity.id}': {}
    }
  }
}

resource config 'Microsoft.Web/sites/config@2024-11-01' = {
  name: 'appsettings'
  parent: logicApp
  properties: {
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'node'
    WEBSITE_NODE_DEFAULT_VERSION: '20'

    // required to access workflow storage via managed identity
    AzureWebJobsStorage__managedIdentityResourceId: logicAppIdentity.id
    AzureWebJobsStorage__credential: 'managedIdentity'
    AzureWebJobsStorage__blobServiceUri: blobStorageAccount.properties.primaryEndpoints.blob
    AzureWebJobsStorage__queueServiceUri: blobStorageAccount.properties.primaryEndpoints.queue
    AzureWebJobsStorage__tableServiceUri: blobStorageAccount.properties.primaryEndpoints.table

    AzureFunctionsJobHost__extensionBundle__id: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
    AzureFunctionsJobHost__extensionBundle__version: '${'[1.*,'}${' 2.0.0)'}'
    APP_KIND: 'workflowApp'
    serviceBus_fullyQualifiedNamespace: '${serviceBusNamespace.name}.servicebus.windows.net'
    AzureCosmosDB_connectionString: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${CONNECTION_STRING_COSMOSDB.name})'
    AzureBlob_blobStorageEndpoint: blobStorageAccount.properties.primaryEndpoints.blob
    APPLICATIONINSIGHTS_CONNECTION_STRING: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${CONNECTION_STRING_APP_INSIGHTS.name})'
    WORKFLOWS_RESOURCE_GROUP_NAME: resourceGroup().name
    WORKFLOWS_SUBSCRIPTION_ID: subscription().subscriptionId
    WORKFLOWS_LOCATION_NAME: location
    WORKFLOWS_TENANT_ID: subscription().tenantId
    WORKFLOWS_MANAGEMENT_BASE_URI: 'https://management.azure.com/'
    office365_ConnectionRuntimeUrl: office365APIConnection.properties.connectionRuntimeUrl
    functionsRuntimeScaleMonitoringEnabled: 'true'
  }
}

//
// API Connections for Logic App
// These are required for managed connectors. After deployed you will need to go the portal, select the API Connector, and authorize the connection.
//

resource dynamicsSpConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'dynamicsSpConnection'
  location: location
  kind: 'V2'
  properties: {
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'dynamicsax')
    }
    parameterValues: {
      'token:clientId': logicApp.identity.principalId
      'token:resourceUri': 'https://api.businesscentral.dynamics.com/'
    }
    displayName: 'dynamicsSpConnection'
  }
}

resource office365APIConnection 'Microsoft.Web/connections@2016-06-01' = {
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
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {}
}

resource serviceBusQueues 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = [
  for name in listQueues: {
    name: name
    parent: serviceBusNamespace
    properties: {}
  }
]

resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2022-01-01-preview' = {
  name: s1topicName
  parent: serviceBusNamespace
  properties: {}
}

resource serviceBusTopicSubscriptions 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-01-01-preview' = [
  for name in listSubscriptionNames: {
    name: name
    parent: serviceBusTopic
    properties: {}
  }
]

// roles to allow the logic app to send and receive messages from the service bus

var serviceBusRoleIds = [
  '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0' // service bus data receiver
  '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39' // service bus data sender
]
resource serviceBusRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in serviceBusRoleIds: {
    scope: serviceBusNamespace
    name: guid(logicApp.id, roleId)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalType: 'ServicePrincipal'
      principalId: logicApp.identity.principalId
    }
  }
]

//
// logging and monitoring
//

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: logAnalyticsWorkspaceTokenName
  location: location
  tags: tags
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsTokenName
  location: location
  tags: tags
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
  tags: tags
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
  tags: tags
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

resource leasesContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-05-15' = {
  name: cosmosLogicAppTriggerLeasesContainerName
  parent: database
  properties: {
    resource: {
      id: cosmosLogicAppTriggerLeasesContainerName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
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

output serviceBus_fullyQualifiedNamespace string = serviceBusNamespace.properties.serviceBusEndpoint
output AzureCosmosDB_connectionString string = cosmosDbAccount.properties.connectionStrings[0]
output AzureBlob_blobStorageEndpoint string = blobStorageAccount.properties.primaryEndpoints.blob
