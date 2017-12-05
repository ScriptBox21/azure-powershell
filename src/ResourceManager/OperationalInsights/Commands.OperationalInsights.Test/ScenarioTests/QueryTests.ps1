﻿function Test-SimpleQuery
{
    $wsId = "DEMO_WORKSPACE"
    $query = "union * | take 10"

    $results = Invoke-AzureRmOperationalInsightsQuery -WorkspaceId $wsId -Query $query -UseDemoKey

    AssertQueryResults $results 10
}

function Test-SimpleQueryWithTimespan
{
    $wsId = "DEMO_WORKSPACE"
    $query = "union * | take 10"
    $timespan = (New-Timespan -Hours 1)

    $results = Invoke-AzureRmOperationalInsightsQuery -WorkspaceId $wsId -Query $query -Timespan $timespan -UseDemoKey

    AssertQueryResults $results 10
}

function Test-ExceptionWithSyntaxError
{
    $wsId = "DEMO_WORKSPACE"
    $query = "union * | foobar"

    Assert-ThrowsContains { Invoke-AzureRmOperationalInsightsQuery -WorkspaceId $wsId -Query $query -UseDemoKey } "BadRequest"
}

function Test-ExceptionWithShortWait
{
    $wsId = "DEMO_WORKSPACE"
    $query = "union *"
    $timespan = (New-Timespan -Hours 24)
    $wait = 1;

    Assert-ThrowsContains { $results = Invoke-AzureRmOperationalInsightsQuery -WorkspaceId $wsId -Query $query -Timespan $timespan -Wait $wait -UseDemoKey } "GatewayTimeout"
}

function AssertQueryResults($results, $takeCount)
{
    Assert-NotNull $results
    Assert-NotNull $results.Results

    $resultsArray = [System.Linq.Enumerable]::ToArray($results.Results)

    Assert-AreEqual $resultsArray.Length $takeCount

    # Tenant ID should always be populated
    Assert-NotNull $resultsArray[0].TenantId
}
