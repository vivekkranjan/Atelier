Class CUSTOM.CORE.Operation.FrameworkDeliveryOperationForSda Extends CUSTOM.CORE.Operation.FrameworkApsDeliveryOperation
{

Property TargetAPSOperation As Ens.DataType.ConfigName [ InitialExpression = "ToBusAdvPatientSearchWsClient" ];

XData MessageMap
{
<MapItems>
<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
<Method>DeliverApsPushNotification</Method>
</MapItem>
</MapItems>
}

Method Prepare(pRequest As HS.Message.Push.DeliveryRequest, ByRef pDataArray As %String) As %Status
{
	set tSC = $$$OK
	Do pRequest.XMLData.Rewind()
	Set tSDAMessage=##class(EnsLib.EDI.XML.Document).ImportFromLibraryStream(pRequest.XMLData,.status)
	//Quit:'..CheckMessageType(tSDAMessage,.tCalculatedTriggerEvt,.tMsgSecurity) 
	Set obj=##class(CUSTOM.CORE.Util.SDADataHelper).%New(pRequest.XMLData)
	Set pDataArray("MRNASSIGNINGAUTH")=obj.GetAssigningAuthorityFromSDA()
	Set pDataArray("MRN")=obj.GetMRNFromSDA()
	Quit tSC
}

Method PopulateNotificationData(pRequest As HS.Message.Push.DeliveryRequest, ByRef pDataArray As %String, ByRef pStopProcessing As %String = 0) As %Status
{
	set status = $$$OK
	Set pDataArray("MSGTYPE")=""
	Set pDataArray("MSGSECURITY")=""
	Set tSDADataHelper = ##class(CUSTOM.CORE.Util.GetDataFromSdaHelper).%New(pRequest.XMLData)
	Set status = tSDADataHelper.GetDataFromSDA(.pDataArray)
	set status = ..PopulateSubscriptionSpecificFields(.pDataArray)
	quit status
}

Method PopulateSubscriptionSpecificFields(ByRef pDataArray As %String) As %Status
{
	Quit $$$OK
}

}
