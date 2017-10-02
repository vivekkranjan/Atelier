Include HS.Common

Class CUSTOM.CORE.Operation.VisitApptLookup Extends Ens.BusinessProcess [ ClassType = persistent ]
{

/// Name of the ECR Manager component, a business host that reads from and writes to the ECR.
Property ECRTarget As Ens.DataType.ConfigName [ InitialExpression = "CUSTOM.EDGE.Operation.Manager" ];

Method AssociateVisitAppt(pMRN As %String, pFacility As %String, pAssignAuth As %String, pApptNo As %String, Output pVisitNo As %String) As %Status
{
	Set tSC=$$$OK
	
		
	Try{
    				
		//Step1 = Call ECR FetchRequest to retrieve Encounter from Appointment Number
		s tSC=..GetEncounterFromApptId(pMRN,pFacility,pAssignAuth,pApptNo,.tVisitNo) Quit:$$$ISERR(tSC)		
		
		//Step2 = Set variable to return visit number
		if (tVisitNo'=""){
			Set pVisitNo = tVisitNo
		}
	}
	Catch ex {
		Set tSC = $$$OK
	}
	Quit tSC
}

Method GetEncounterFromApptId(pMRN As %String, pFacility As %String, pAssignAuth As %String, pApptNo As %String, Output pVisitNo As %String) As %Status
{
	Set tSC=$$$OK
	
	#dim tResponse As HS.Message.EPRFetchNotification
	Set tRequest=##class(HS.Message.ECRFetchRequest).%New()
	Set tRequest.Facility=pFacility
	Set tRequest.AssigningAuthority=pAssignAuth
	Set tRequest.MRN=pMRN
	Set tSC=..SendRequestSync(..ECRTarget,tRequest,.tResponse) Quit:$$$ISERR(tSC) 
	
	Set pVisitNo=""	
	
	IF $$$ISOK(tSC),tResponse.Action'=0 {
		Set:tResponse.QuickStreamId'="" tQuickStream=##Class(HS.SDA3.QuickStream).%OpenId(tResponse.QuickStreamId)
		Set tSDA=$S(tQuickStream'="":tQuickStream,tResponse.ContentStream="":tResponse.Content,1:tResponse.ContentStream)

		//Correlate XML with HS.SDA3.Appointment
		Set tReader = ##class(%XML.Reader).%New()
		Do tReader.OpenStream(tSDA)
		Do tReader.Correlate("Appointment","HS.SDA3.Appointment")
		#dim tSDAAppointment As HS.SDA3.Appointment
		Set tFillerApptId=""		
		While tReader.Next(.tSDAAppointment, .tSC) {
			if (pApptNo=tSDAAppointment.FillerApptId){
				 Set pVisitNo=tSDAAppointment.EncounterNumber
			}
			Quit:$$$ISERR(tSC)
		}
	}
	Quit tSC
}

Storage Default
{
<Data name="VisitApptLookupDefaultData">
<Subscript>"VisitApptLookup"</Subscript>
<Value name="1">
<Value>ECRTarget</Value>
</Value>
</Data>
<DefaultData>VisitApptLookupDefaultData</DefaultData>
<Type>%Library.CacheStorage</Type>
}

}
