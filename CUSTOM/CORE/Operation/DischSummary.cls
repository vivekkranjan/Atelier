Include %ZEN.ReportUtil

Class CUSTOM.CORE.Operation.DischSummary Extends CUSTOM.CORE.Operation.BaseEmailOperation
{

Parameter SubscriptionName As %String;

Parameter EmailSubject As %String;

Parameter ADAPTER = "EnsLib.File.OutboundAdapter";

Property Adapter As EnsLib.File.OutboundAdapter;

Property EmailGlobalSubscript As %String [ InitialExpression = {..#SubscriptionName} ];

Parameter Cohort As %String;

Property TargetEmailOperation As Ens.DataType.ConfigName [ InitialExpression = "CUSTOM.Util.Operation.Email" ];

Property OutputFileNamePrefix As %String(MAXLEN = 100);

Property DeleteAfterSend As %Boolean [ InitialExpression = 1 ];

XData MessageMap
{
<MapItems>
<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
<Method>EnrollEncounter</Method>
</MapItem>
<MapItem MessageType="HS.Message.XMLMessage"> 
<Method>CreateAndSendPdf</Method>
</MapItem>
</MapItems>
}

/// Push DeliveryRequest will use this method instead of the BaseEmailOperation's SendNotification.
/// We don't want to send an email now. Instead, put the encounter into the NotificationStatus table.
Method EnrollEncounter(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	#Dim tRS As %SQL.StatementResult
	Set status=$SYSTEM.Status.OK()
	Try {
		// This will populate the data array
		Set tHL7Message = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pRequest.OtherData,.status)
		Set tHL7DataHelper = ##class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
		Set tSC = tHL7DataHelper.GetDataFromHL7(tHL7Message,.tDataArray)
				
		Set tMRN = $Get(tDataArray("MRN"))
		Set tAA = $Get(tDataArray("MRNASSIGNINGAUTH"))
		Set tEncNum = $Get(tDataArray("VISITNUMBER"))
			
		If (tMRN="") || (tAA="") || (tEncNum="") {
			$$$ThrowStatus($$$ERROR($$$GeneralError, "MRN, AA, and Encounter Number are required to process"))
		}
		
		Set tSQL = "select top 1 ID from CUSTOM_Push.NotificationStatus where SubscriptionName=? and MRN=? and AssigningAuth=? and EncounterNumber=?"
		Set tRS = ##class(%SQL.Statement).%ExecDirect(,.tSQL,..#SubscriptionName, tMRN, tAA, tEncNum)
		If (tRS.%SQLCODE = 0) {
			$$$LOGINFO("Encounter #"_tEncNum_" is already in NotificationStatus for Subscription_"_..#SubscriptionName)
		} Else {
			Set tObj = ##class(CUSTOM.Push.NotificationStatus).%New()
			Set tObj.SubscriptionName = ..#SubscriptionName
			Set tObj.MPIID = pRequest.MPIID
			Set tObj.MRN = tMRN
			Set tObj.AssigningAuthority = tAA
			Set tObj.EncounterNumber = tEncNum
			Set tObj.Status = "Pending"
			Set tObj.CreatedOn = $ZDateTime($Horolog,3,1)
			Set tObj.UpdatedOn = tObj.CreatedOn
			Do tObj.AdditionalInfo.SetAt($Get(tDataArray("ADMITTIME")),"FromTime")
			Set tSC = tObj.%Save()  $$$ThrowOnError(tSC)
		}

		Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
		Set pResponse.OKToPurge=1
	} Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
}

Method IsSendEmail(pPatDataArray As %String) As %Boolean [ Private ]
{
	Quit 1
}

/// Generates PDF from FO XML and attaches the PDF to an EmailRequest
/// 
/// Assumption - Additional contains patient/encounter metadata and ContentStream is an FO XML.
/// 
Method CreateAndSendPdf(pRequest As HS.Message.XMLMessage, Output pResponse As Ens.StringResponse) As %Status
{
	Set tSC = $$$OK
	Set tDateTime = $ZStrip($ZDateTime($Horolog,8),"*PW")
	Set tFoFileName= pRequest.Name_".fo"
	Set tOutFileName =  ..OutputFileNamePrefix_pRequest.Name_".pdf"
	Try{
		If $IsObject(pRequest.ContentStream){
			Do ..RenderPDF(tFoFileName, tOutFileName, pRequest.ContentStream, .tStream)
			Set tAttachments = ##class(%Library.ListOfObjects).%New()
			Set tSC = tAttachments.Insert(tStream)  $$$ThrowOnError(tSC)
			
			Set tSubject = "PHI: "_..#EmailSubject_" - Discharge Summary for encounter at "_pRequest.AdditionalInfo.GetAt("Facility")
			Set pEmailKey = ""
			If (..IsSendEmail(.tDataArray)=1) { 			;For Sending Discharge Summaries through Email
				Do ..CreateEmailBody(pRequest, .tHtml)
				Set tDataArray("EMAILSUBJECT") = tSubject
				Set tDataArray("ATTACHMENTNAME",1) = tOutFileName
				Set tSC=..SendEmail(tHtml,tAttachments,.tDataArray,.pEmailKey)  $$$ThrowOnError(tSC)			
			}
			Set tSC=..AdditionalCustomSettingCheck(pRequest,.pResponse)
			$$$ThrowOnError(tSC)
			// Clean up
			If (..DeleteAfterSend = 1) {
				Set tSC = ..Adapter.Delete(tFoFileName)
				If $$$ISERR(tSC) {
					$$$LOGERROR("Error deleting FO file: "_$SYSTEM.Status.GetErrorText(tSC))
				}
				Set tSC = ..Adapter.Delete(tOutFileName)
				If $$$ISERR(tSC) {
					$$$LOGERROR("Error deleting PDF file: "_$SYSTEM.Status.GetErrorText(tSC))
				}
			}
			
			Set tMRN = pRequest.AdditionalInfo.GetAt("MRN")
			Set tAA = pRequest.AdditionalInfo.GetAt("AssigningAuth")
			Set tEncNum = pRequest.AdditionalInfo.GetAt("EncounterNumber")
			Set tSC = ..UpdateNotificationStatus(tAA, tMRN, tEncNum)  $$$ThrowOnError(tSC)
			
			Set tFromTime = ""
			Try {
				Set tFromTime = ##class(CUSTOM.CORE.Util.DataDescriptionLookupAndFormator).HL7ToTimestamp(pRequest.AdditionalInfo.GetAt("FromTime"))
			} Catch (ex) {
				$$$LOGWARNING("Badly formatted FromTime: "_pRequest.AdditionalInfo.GetAt("FromTime"))
			}
			
			/* Removed SDT-1651
			Set tSC = ..AddNotificationData(..#SubscriptionName, 
				tSubject,
				tMRN,
				tAA,
				pRequest.AdditionalInfo.GetAt("FirstName"),
				pRequest.AdditionalInfo.GetAt("LastName"),
				pEmailKey,
				tFromTime)	
			*/
			//Currently we are updating Notification Metric only if the discharge summary is sent via email notification.
			If (..IsSendEmail(.tDataArray)=1) {
				Set tDataArray("SUBSCRIPTIONSUBJECT")=..#SubscriptionName
				Set tDataArray("MRN")=tMRN
				Set tDataArray("LASTNAME")=pRequest.AdditionalInfo.GetAt("LastName")
				Set tDataArray("FIRSTNAME")=pRequest.AdditionalInfo.GetAt("FirstName")
				Set tDataArray("MRNASSIGNINGAUTH")=tAA
				Set tDataArray("FROMTIME")=tFromTime
				Set tDataArray("COHORT")=..#Cohort
				Set tDataArray("FACILITY")=pRequest.AdditionalInfo.GetAt("Facility")
				Set tHospSvc = pRequest.AdditionalInfo.GetAt("HospitalService")
				If ($Piece(tHospSvc,"^",2) '= "") Set tHospSvc = $Piece(tHospSvc,"^",2)
				Set tDataArray("HOSPITALSVC")=tHospSvc
				Set tDataArray("ADMITTIME")=$ZStrip(pRequest.AdditionalInfo.GetAt("FromTime"),"*P")
				Set tDataArray("DISCHARGETIME")=$ZStrip(pRequest.AdditionalInfo.GetAt("ToTime"),"*P")
				Set tDataArray("EVENTDESC")="Discharge"
				Set tDataArray("MPIID")=pRequest.AdditionalInfo.GetAt("MPIID")
				Set tDataArray("ENCTYPE")=pRequest.AdditionalInfo.GetAt("EncounterType")
				
				
				Set tNotificationDataRowId = ""
				Set tSC=##Class(CUSTOM.CORE.Util.NotificationMetricHelper).AddNotificationDataArray(.tDataArray,pRequest.%Id(),pEmailKey,.tNotificationDataRowId)	; AA SDT-1651 10/13/2015 - Updated to use Util class to log Notification Data	
			}			
		} 
	}Catch (ex) {
		Set tSC = ex.AsStatus()
		$$$LOGERROR("Error sending PDF: "_$SYSTEM.Status.GetErrorText(tSC))
	}
	Quit tSC
}

// This call can be overidden by Inherited Class

Method AdditionalCustomSettingCheck(pRequest As HS.Message.XMLMessage, Output pResponse As Ens.StringResponse) As %Status
{
	Set tSC = $$$OK
	Quit tSC
}

Method RenderPDF(pFoFileName As %String, pOutFileName As %String, pFoStream As %Stream.Object, Output pStream As %Stream.GlobalCharacter)
{
	Set tSC = ..Adapter.PutStream(pFoFileName, pFoStream)  $$$ThrowOnError(tSC)

	If ('##class(%File).Exists($$$fopbat)) {
		$$$ThrowStatus($$$ERROR($$$GeneralError,"PDF Renderer not found: "_$$$fopbat))				
	}

	Set tPDFRenderer = $$$fopbat
	Set tFoPathAndFile = ..Adapter.FilePath_"/"_pFoFileName
	Set tPDFPathAndFile = ..Adapter.FilePath_"/"_pOutFileName
	Set tCmd = tPDFRenderer_" "_tFoPathAndFile_" "_tPDFPathAndFile
	Set tRet = $ZF(-1,tCmd)
	
	If (tRet '= 0) {
		$$$ThrowStatus($$$ERROR($$$GeneralError,"PDF rendering failed with status="_tRet_". Command: "_tCmd))
	}
	
	Set tStream = ##class(%Stream.GlobalCharacter).%New()
	Set tSC = ..Adapter.GetStream(pOutFileName, .pStream)  $$$ThrowOnError(tSC)
}

Method CreateEmailBody(pRequest As HS.Message.XMLMessage, Output pHtml As %String)
{
	#Define addrow(%cap,%val) "<tr><td style='padding-right:20px;'>"_$ZCVT(%cap_":","O","HTML")_"</td><td>"_$ZCVT(%val,"O","HTML")_"</td></tr>"
	
	Set pHtml = ""
	
	Set tLastName = pRequest.AdditionalInfo.GetAt("LastName")
	Set tFirstName = pRequest.AdditionalInfo.GetAt("FirstName")
	Set tFacility = pRequest.AdditionalInfo.GetAt("Facility")
	Set tHospSvc = pRequest.AdditionalInfo.GetAt("HospitalService")
	If ($Piece(tHospSvc,"^",2) '= "") Set tHospSvc = $Piece(tHospSvc,"^",2)
	
	Set pHtml = pHtml_"<p style='max-width:700px;'>"_$ZConvert(tFirstName_" "_tLastName,"O","HTML")_
		" has been discharged from "_$ZConvert(tFacility,"O","HTML")_
		". Please see attached discharge summary (PDF).</p>"
		
	Set pHtml = pHtml_"<table style='border-collapse:collapse; margin-top:1em; bottom:1em;'><tbody>"_
		$$$addrow("Patient Name", tLastName_", "_tFirstName)_
		$$$addrow("MRN", pRequest.AdditionalInfo.GetAt("MRN"))_
		$$$addrow("Facility", tFacility)_
		$$$addrow("Visit Number", pRequest.AdditionalInfo.GetAt("EncounterNumber"))_
		$$$addrow("Hospital Service", tHospSvc)_
		$$$addrow("Admit Time", pRequest.AdditionalInfo.GetAt("FromTime"))_
		$$$addrow("Discharge Time", pRequest.AdditionalInfo.GetAt("ToTime"))
	Do ..AddExtraRows(pRequest,.pHtml)
	Set pHtml = pHtml_"</tbody></table>"
	Set pHtml = pHtml_"<p><i>Please do not reply to this email</i></p>"
}

Method AddExtraRows(pRequest As HS.Message.XMLMessage, Output pHtml As %String)
{
}

Method UpdateNotificationStatus(pAA As %String, pMRN As %String, pEncounterNumber As %String) As %Status
{
	#Dim tRS As %SQL.StatementResult
	Set tSC = $$$OK
	Try{
		//set tSubName = ##class(CUSTOM.ACCESS01.HealthHome.Operation.DischSummary).#SubscriptionName
		Set tSubName = ..#SubscriptionName
		Set tSQL = "update CUSTOM_Push.NotificationStatus set Status='Sent' where AssigningAuthority=? and MRN=? and EncounterNumber=? and SubscriptionName=?"
		Set tRS = ##class(%SQL.Statement).%ExecDirect(,.tSQL,pAA,pMRN,pEncounterNumber,tSubName)
		If (tRS.%SQLCODE < 0) {
			$$$ThrowStatus($$$ERROR($$$GeneralError,"Error updating notification status: "_tRS.%SQLCODE_"/"_tRS.%Message))
		}
	} Catch (ex) {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Method FTPPDF(pRequest As HS.Message.XMLMessage, Output pResponse As Ens.StringResponse, pFTPOperation As %String) As %Status
{
	Set tSC = $$$OK
	Set tOutFileName =  ..OutputFileNamePrefix_pRequest.Name_".pdf"
	If (pFTPOperation '= "") {
		Set tTargetFile = tOutFileName
		Set tStream = ##class(%Stream.GlobalCharacter).%New()
		Set tSC = ..Adapter.GetStream(tTargetFile, .tStream)
		$$$ThrowOnError(tSC)			
		Set tContainer = ##class(Ens.StreamContainer).%New()
		Set tContainer.Stream = tStream
		Set tContainer.OriginalFilename = tTargetFile		
		Set tSC = ..SendRequestSync(pFTPOperation, tContainer, .pResponse)
		$$$ThrowOnError(tSC)
		If (..TargetArchiveOperation '= "") {
			Set tSC = ..SendRequestAsync(..TargetArchiveOperation, tContainer)
			$$$ThrowOnError(tSC)
		}
	}	
	Quit tSC
}

/// todo: breakdown more 
Method SendEmail(pHtml As %String, pAttStreams As %Library.ListOfObjects, ByRef pDataArray As %String, ByRef pEmailKey As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Try {
			Set pRecipientList=""
			Set tMail=##Class(CUSTOM.Util.Message.EmailRequest).%New()
			Set tEnv=$ZConvert(##Class(Workbench.SourceControl.Commander).GetEnvironment(),"u")
			Set mailToList=..getEmailToList(.pDataArray)
			Set tMailToList=..EmailToList_","_mailToList
			For i=1:1:$Length(tMailToList,",") {
				Set tTo=$Piece(tMailToList,",",i)
				Continue:tTo=""
				Do tMail.To.Insert(tTo)
			}
			For i=1:1:$Length(..EmailBccList,","){
				Set tBcc = $Piece(..EmailBccList,",",i)
				Continue:tBcc=""
				Do tMail.Bcc.Insert(tBcc)
			}
			///Do tMail.Bcc.Insert("crusch@nshs.edu") ;Chris wants to be copied always.

			If '(tEnv="PROD"){
				If ($Data(^QAEmailAddress(..EmailGlobalSubscript),tData)=1){
					Set tCntr=1
					While(tCntr>0){
						If $Piece(tData,",",tCntr)'=""{
							Do tMail.To.Insert($Piece(tData,",",tCntr))
							Set tCntr=tCntr+1
						}
						Else{
							Set tCntr=0
						}
					}
				}
			}
			Set tMail.Subject=pDataArray("EMAILSUBJECT")
			Set tMail.From=..EmailFrom
			Set tMail.Message=pHtml
			
			If ($IsObject(pAttStreams)) {
				For i=1:1:pAttStreams.Count() {
					Set tMail.AttachmentStream = pAttStreams.GetAt(i)
					Set tMail.AttachmentFileName = pDataArray("ATTACHMENTNAME",i)
					Set tMail.AttachmentIsBinary = 1 // hardcoded for now
					Quit // Only 1 attachment is supported for now
				}
			}
			For i=1:1:tMail.To.Count(){
				Set pRecipientList=pRecipientList_tMail.To.GetAt(i)_","
			}
			Set pRecipientList=$Extract(pRecipientList,1,$Length(pRecipientList)-1)
			Set pDataArray("RECIPIENTLIST")=pRecipientList
			Set tResponse=##Class(CUSTOM.Util.Message.EmailResponse).%New()
			Set tSC=..SendRequestSync(..TargetEmailOperation, tMail, .tResponse)
			If ($$$ISOK(tSC) && (tResponse.EmailSent = 1)) {
				Set pEmailKey=tResponse.EmailKey
			}
			
							
			If (..TargetArchiveOperation '= "") {
				Set tSC = ..SendRequestAsync(..TargetArchiveOperation, tMail)
				$$$ThrowOnError(tSC)
			}
	} Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
}

}
