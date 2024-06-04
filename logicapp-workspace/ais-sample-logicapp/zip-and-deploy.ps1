if ($args.Length -lt 2) {
    Write-Host "Usage: zip-and-deploy.ps1 <logicAppName> <resourceGroup>"
    exit 1
}

$logicAppName=$args[0]
$resourceGroup=$args[1]

$subscriptionId = (az account show | ConvertFrom-Json | Select id).id

Write-Host "####################################"
Write-Host "Logic App Name:  $logicAppName"
Write-Host "Resource Group:  $resourceGroup"
Write-Host "Subscription ID: $subscriptionId"
Write-Host "####################################"

mkdir .\logicAppDeploy -Force

Write-Host
Write-Host "## Copying files to deployment folder"

Copy-Item -r .\Artifacts .\logicAppDeploy  -Force

Copy-Item -r .\s1-receive .\logicAppDeploy  -Force
Copy-Item -r .\s2-receive .\logicAppDeploy  -Force
Copy-Item -r .\s3-receive .\logicAppDeploy -Force

Copy-Item -r .\s1-process .\logicAppDeploy -Force
Copy-Item -r .\s2-process .\logicAppDeploy -Force
Copy-Item -r .\s3-process .\logicAppDeploy -Force

Copy-Item -r .\s1-sub1 .\logicAppDeploy -Force
Copy-Item -r .\s1-sub2 .\logicAppDeploy -Force
Copy-Item -r .\s1-sub3 .\logicAppDeploy -Force

Copy-Item .\connections.json .\logicAppDeploy -Force
Copy-Item .\host.json .\logicAppDeploy -Force
Copy-Item .\parameters.json .\logicAppDeploy -Force

Write-Host "## Zipping deployment folder"

Compress-Archive -Path .\logicAppDeploy\* -DestinationPath .\logicAppDeploy.zip -Force

Write-Host "## Deploying Logic App"
Write-Host

az logicapp deployment source config-zip --name $logicAppName `
   --resource-group $resourceGroup --subscription $subscriptionId `
   --src .\logicAppDeploy.zip

Write-Host
Write-Host "## Cleaning up"

Remove-Item -r .\logicAppDeploy  
Remove-Item .\logicAppDeploy.zip 

Write-Host "## Complete"