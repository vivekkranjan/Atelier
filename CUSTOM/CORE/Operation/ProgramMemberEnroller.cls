Class CUSTOM.CORE.Operation.ProgramMemberEnroller Extends Ens.BusinessOperation
{

/// Program to enroll to.
Property ProgramName As %String;

Parameter SETTINGS = "ProgramName,MebershipLoadFrequency,MembershipThreshold";

/// Frequency of the Membership Data Sync (In Months)
Property MebershipLoadFrequency As %Integer [ InitialExpression = 1 ];

/// Buffer time to allow membership after scheduled Membership Data Sync (In Days)
Property MembershipThreshold As %Integer [ InitialExpression = 5 ];

XData MessageMap
{
<MapItems>
	<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
		<Method>HandleDeliveryRequest</Method>
	</MapItem>
</MapItems>
}

Method HandleDeliveryRequest(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	Set status=$System.Status.OK()
	Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
	Set pResponse.OKToPurge=1
	Try {
		Set status=..Enroll(pRequest.XMLData)
		If ($System.Status.IsError(status)){
			Throw ##Class(%Exception.StatusException).CreateFromStatus(status)
		}
	}Catch(exception){
		Set status=exception.AsStatus()
		$$$LOGERROR($SYSTEM.Status.GetErrorText(status))
	}
	Quit status
}

Method Enroll(pSDAStream As %GlobalCharacterStream) As %Status
{
	#Dim enrollmentResponse As CUSTOM.REGISTRY.ProgramRegistryService.Message.AddUpdateProgramMemberResponse
	Set enrollmentResponse=""
	Set status=$System.Status.OK()

	Set enrollmentHelper=##Class(CUSTOM.CORE.Util.MemberEnrollment).%New()
	Set sdaHelper=##Class(CUSTOM.CORE.Util.SDADataHelper).%New(pSDAStream)
	Set hieRiskProgram = sdaHelper.GetHieRiskProgramFromSDA()
	//get HieRiskProgram value from the SDA and if it is empty, enroll ; if it is "NA" then dont enroll.
	If (hieRiskProgram = "NA"){
		$$$LOGINFO("Member need not be enrolled in risk program. Program name : "_..ProgramName)
		Quit status
	}elseif (hieRiskProgram = ""){
		Set mrn=sdaHelper.GetMRNFromSDA()
		Set assigningAuthority=sdaHelper.GetAssigningAuthorityFromSDA()
		Set fromTime=$Select(sdaHelper.IsNewPatient=1:$ZDateTime($Horolog,3), 1:"")	
		Set today=$ZDateTime($Horolog,3,1)
		Set nextLoadTime=##Class(%SYSTEM.SQL).DATEADD("MM",..MebershipLoadFrequency,today)
		Set toTime= ##Class(%SYSTEM.SQL).DATEADD("DD",..MembershipThreshold,nextLoadTime)
	
		Set enrollmentRequest=enrollmentHelper.CreateAddUpdateProgramMemberRequest(assigningAuthority,mrn,..ProgramName,fromTime,toTime)
		Set enrollmentResponse=##Class(CUSTOM.REGISTRY.ProgramRegistryService.Message.AddUpdateProgramMemberResponse).%New()
		Set status=enrollmentHelper.AddUpdateProgramMember(enrollmentRequest,.enrollmentResponse)
	}
	
	Quit status
}

}
