/// A task to send monitoring data to ZpmHub
Class ZPMHUB.Task Extends %SYS.Task.Definition
{

Parameter TaskName = "ZpmHubMonitor";

/// This method is responsible for executing the task.
Method OnTask() As %Status
{
  $$$QuitOnError(..SendEnvironmentData())
  quit $$$OK
}

ClassMethod IsLegacy() As %Boolean [ CodeMode = expression ]
{
$SELECT(##class(%Dictionary.ClassDefinition).%ExistsId("%IPM.Main"): 0, ##class(%Dictionary.ClassDefinition).%ExistsId("%ZPM.PackageManager"): 1)
}

ClassMethod SendEnvironmentData()
{
    set ns=""
    for {
        set ns=$order(^%ZPMHUB(ns))
        quit:ns=""
        do ..SendSingleEnvironment(ns)
    }
    quit $$$OK
}

ClassMethod SendSingleEnvironment(ns As %String) As %Status
{
    new $namespace
    set $namespace=ns
    if '##class(%Dictionary.ClassDefinition).%ExistsId("ZPMHUB.Setup") {
        quit $$$ERROR($$$GeneralError,"ZpmHub class was removed from "+$namespace)
    }
    Try {
        set tIsLegacy = ..IsLegacy()
    } catch ex {
        If ex.Name = "<SELECT>" {
            Return $$$ERROR($$$GeneralError,"You need to install ZPM Package Manager for ZpmHub to work")
        } else {
            Return ex.AsStatus()
        }
    }
    set Setup=##class(ZPMHUB.Setup).%OpenId($Namespace)
    if 'Setup.IsMonitoringEnabled quit $$$OK

    set jsonData=..GetSingleEnvironmentData(ns)

    If tIsLegacy {
        set config=##class(%ZPM.PackageManager.Client.REST.PackageManagerClient).%New()
    } Else {
        set config=##class(%IPM.Repo.Remote.PackageService).%New()
    }
    set config.Location=Setup.Server_"api/environment/"
    set config.Username="token"
    set config.Password=Setup.Token

    Set tRequest = config.GetHttpRequest()
    
    Set tRequest.ContentType = "application/json"
    Do jsonData.%ToJSON(tRequest.EntityBody) 
    Set tSC = tRequest.Post($$$URLENCODE(tRequest.Location))
    If ($$$ISERR(tSC) || (tRequest.HttpResponse.StatusCode'=200)) {
        quit $$$ERROR($$$GeneralError,"Error Sending Monitoring Data")
    }
    quit $$$OK
}

ClassMethod GetSingleEnvironmentData(ns As %String) As %Status
{
    new $Namespace
    set Setup=##class(ZPMHUB.Setup).%OpenId($Namespace)

    set jsonResult={}
    set jsonResult.zv=$ZVersion
    set jsonResult.time=$h
    set jsonResult.environmentName=Setup.EnvironmentName
    set jsonResult.serverName=Setup.ServerName
    set jsonResult.namespace=ns
    If ..IsLegacy() {
        $$$QuitOnError(##class(%ZPM.PackageManager).GetListModule(ns,.packageList,0))
    } Else {
        $$$QuitOnError(##class(%IPM.Main).GetListModule(ns,.packageList,0))
    }
    set package="", jsonResult.packages=[]
    for {
        set package=$order(packageList(package))
        quit:package=""
        set packageData={
            "name": (package),
            "version": (packageList(package)),
            "description": ($listget(packageList(package,"L"),3))
        }
        do jsonResult.packages.%Push(packageData)
    }
    set $namespace="%SYS"
    set monitorData=##class(SYS.Monitor.SAM.Sensors).PrometheusMetrics()
    set $namespace=ns
    set jsonResult.metrics=monitorData
    quit jsonResult
}

}
