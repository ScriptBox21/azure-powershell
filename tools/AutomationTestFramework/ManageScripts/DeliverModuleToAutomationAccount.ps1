﻿if (!$azureConfig) {
    . "$PSScriptRoot\AzureConfig.ps1"
}

<#
.SYNOPSIS
Uploads module to Azure Storage Account container
.PARAMETER modulePath
Path to the directiory where module is located
.PARAMETER moduleName
Name of the module without extension
.PARAMETER subscriptionName
Subscription name of the Azure Storage Account
.PARAMETER storageAccountName
Azure Storage Account Name
.PARAMETER resourceGroupName
Resource group name of the Azure Storage Account
.PARAMETER containerName
Container name in the Azure Storage Account
.NOTES
This is the first step of the two steps upload to Azure Automation Account action
#>
function UploadModuleToContainer (
     [string] $modulePath
    ,[string] $moduleName
    ,[string] $subscriptionName
    ,[string] $storageAccountName
    ,[string] $resourceGroupName
    ,[string] $containerName) {

    $subscriptionName, $resourceGroupName, $storageAccountName,  $containerName = DefaultIfNotSpecifiedSA $subscriptionName $resourceGroupName $storageAccountName  $containerName
    Write-Host "Getting Azure storage account key..." -ForegroundColor Green

    $storageAccountKey = Get-AzureRmStorageAccountKey -StorageAccountName $storageAccountName -ResourceGroupName $resourceGroupName -Verbose -ErrorAction Stop
    $key1 = $storageAccountKey.Value[0];
    Write-Host "Creating Azure storage account context..." -ForegroundColor Green
    $ctx = New-AzureStorageContext $storageAccountName -StorageAccountKey $key1 -ErrorAction Stop
    Write-Host "Uploading module to Azure storage container..." -ForegroundColor Green
    $blobName = "$moduleName.zip"
    $null = Set-AzureStorageBlobContent -Container $containerName  -File "$modulePath\$blobName" -Blob $blobName -Context $ctx -Force -ErrorAction Stop
    $now = Get-Date;
    Write-Host "Creating Azure storage blob SAS URL..." -ForegroundColor Green
    $sasTokenURL = New-AzureStorageBlobSASToken -Container $containerName -Blob $blobName -Context $ctx -Permission rwd -StartTime $now.AddHours(-1) -ExpiryTime $now.AddHours(1) -FullUri -ErrorAction Stop
    return $sasTokenURL
}

<#
.SYNOPSIS
Uploads module from Azure Storage Account to Automation Account
.DESCRIPTION
Module should be uploaded to Azure Storage Account first
.PARAMETER automationAccountName
Azure Automation Account name
.PARAMETER subscriptionName
Subscription name of the Azure Automation Account
.PARAMETER resourceGroupName
Resource group name of the Azure Automation Account
.PARAMETER moduleName
Name of the module
.PARAMETER url
URL of the the publicly accessible module.
If URL is a private blob URL, the URL should be a SAS URL.
.NOTES
For some reason Set-AzureRmAutomationModule doesn't work. 
New-AzureRmAutomationModule have to be used even if the module already exsists on Automation Accunt
#>
function UpdateMouduleToAutomationAccount ( 
     [string] $automationAccountName
    ,[string] $subscriptionName
    ,[string] $resourceGroupName
    ,[string] $moduleName
    ,[string] $url ) {
    
    $subscriptionName, $automationAccountName, $resourceGroupName = DefaultIfNotSpecifiedAA $subscriptionName $automationAccountName $resourceGroupName
    Write-Host "Adding module '$moduleName' to Azure Automation account..." -ForegroundColor Green
    $null = New-AzureRmAutomationModule -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName -Name $moduleName -ContentLink $url -ErrorAction Stop
}

<#
.SYNOPSIS
Cheks provision state of the every module in the $moduleList
.DESCRIPTION
Read modules provision state until it's Succeded of Failed
.PARAMETER automationAccountName
Azure Automation Account name where module got uploaded.
If not specified, value from $azureConfig get used.
.PARAMETER subscriptionName
Subscription name of Azure Automation Account where module got uploaded 
If not specified, value from $azureConfig get used.
.PARAMETER resourceGroupName
Resource group name of Azure Automation Account where module got uploaded 
If not specified, value from $azureConfig get used.
.PARAMETER moduleList
List of moules to check status for
#>
function CheckModuleProvisionState (     
     [string] $automationAccountName
    ,[string] $subscriptionName
    ,[string] $resourceGroupName
    ,[string[]] $moduleList ) {

    $subscriptionName, $automationAccountName, $resourceGroupName = DefaultIfNotSpecifiedAA $subscriptionName $automationAccountName $resourceGroupName

    $azureContext = (Get-AzureRmContext)
    if ($azureContext.Subscription.Name -ne $subscriptionName) {
        Write-Host "Switching subscription to '$subscriptionName'"
        $null = Get-AzureRmSubscription –SubscriptionName $subscriptionName -ErrorAction Stop | Select-AzureRmSubscription -ErrorAction Stop
    }
    
    $sleepSec = 10
    $attempsQnty = 20
    $counter = 1;

    $statusMap = @{}
    $moduleList | ForEach-Object {
        $statusMap.Add($_, $null)
    }

    Write-Host "Checking modules provision state, number of requests is $attempsQnty..." -ForegroundColor Green
    while ($counter -lt $attempsQnty) {
        $inProgressModules = $statusMap.GetEnumerator() | Where-Object {$_.Value -eq $null} | ForEach-Object { $_.Key }
        $inProgressModules | ForEach-Object {
            $moduleName = $_
            $module = Get-AzureRmAutomationModule -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName -Name $moduleName -ErrorAction Stop
            $provisioningState = $module.ProvisioningState
            Write-Host "`t$moduleName provision state is ""$provisioningState"""
            
            $progressActivity = "Checking module '$moduleName' provision state"
            $percentComplete =  $counter/$attempsQnty*100
            Write-Progress -Activity  $progressActivity -PercentComplete $percentComplete -Status "Current provision state is '$provisioningState'"

            if (($provisioningState -eq 'Succeeded') -or ($provisioningState -eq 'Failed'))  {
                $statusMap.Set_Item($moduleName, ($provisioningState -eq 'Succeeded'))
                Write-Progress -Activity  $progressActivity -Completed
            }
            
        }
        
        $inProgressModules = $statusMap.GetEnumerator() | Where-Object {$_.Value -eq $null}
        if ($inProgressModules.Count -gt 0) {
            Write-Host "`t#$counter waiting $sleepSec sec..."
            Start-Sleep -Seconds $sleepSec 
            $counter++
        } else {
            break
        }
    }
    
    if ($counter -eq $attempsQnty) {
        $totalCheckTime =  $attempsQnty*$sleepSec
        Write-Host "Looks like the provision is not finished after $totalCheckTime seconds"   
    }
    
    #Write-Host "Module added, final provision state is ""$provisioningState"" " -ForegroundColor Green 
    $statusMap
}

<#
.SYNOPSIS
Uploads local module to Azure Automation Account 
.DESCRIPTION
Since it's not allowed to upload a local module directly to Automation Account,
the module gets first uploaded to Azure Storage Account, 
and then from the Storage Account to Automation Account.
.PARAMETER modulePath
Path to the directory where the module is located
.PARAMETER moduleName
Name of the module without extension
.EXAMPLE
DeliverModuleToAutomationAccount -modulePath "D:\pkgs\ToUpload" -moduleName 'AzureRM.Compute'
This command will upload "D:\pkgs\ToUploadAzureRM.Compute.zip" file to Azur Automaiton Account
.NOTES
$azureConfig map provides Azure relates settings
#>
function DeliverModuleToAutomationAccount (
     [string] $modulePath
    ,[string] $moduleName) {

    $url = UploadModuleToContainer `
        -modulePath $modulePath `
        -moduleName $moduleName `
    $url

    UpdateMouduleToAutomationAccount `
        -moduleName $moduleName `
        -url $url
}