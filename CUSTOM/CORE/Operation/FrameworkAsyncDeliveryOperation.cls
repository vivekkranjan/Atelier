Class CUSTOM.CORE.Operation.FrameworkAsyncDeliveryOperation Extends CUSTOM.CORE.Operation.FrameworkDeliveryOperation
{

Property HL7Subscription As %String;

Property DeliveryOperation As %String;

Property RiskEdgeMRN As %String;

Property RiskEdgeAssigningAuthority As %String;

Property RankOrScore As %String;

Property LaceScore As %String;

Property LaceScoreFromSda As %String;

Property FromTime As %TimeStamp;

XData MessageMap
{
<MapItems>
<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
<Method>DeliverAsyncPushNotification</Method>
</MapItem>
<MapItem MessageType="CUSTOM.Util.Message.ENFrameworkAsyncQueueMonitorServiceRequest"> 
<Method>DeliverAsyncScheduledPushNotification</Method>
</MapItem>
</MapItems>
}

Method DeliverAsyncPushNotification(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	Set tSC=$$$OK
	Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
	Set pResponse.OKToPurge=1
	Try {
		///Fetch Lace from incoming SDA
		Set tSDADataHelper=##class(CUSTOM.CORE.Util.SDADataHelper).%New()
		Set tSDADataHelper.pSDAStream=pRequest.OtherData
		Do tSDADataHelper.GetLaceScoreFromSda(.Lace,,.tSC)
		Set ..LaceScore = Lace 
		
		// Fetch MRN, AA, EncNum
		Set tMRN = tSDADataHelper.GetMRNFromSDA()
		Set tAA = tSDADataHelper.GetAssigningAuthorityFromSDA()
		Set tEncNum = tSDADataHelper.GetEncounterNumberFromSDAObservation()
		
		//Update Lace in Clinical Board
		Set tSC = ..UpdateLace(tMRN,tAA,tEncNum,Lace)
		
		
		//Get Active Requests (Request for which mail is not yet sent) from Queue table for MRN AA EncNum
		Set tActiveRecords = ##class(CUSTOM.Util.Message.FrameworkAsyncQueueResponse).%New()
		Set tSC = ##class(CUSTOM.CORE.Util.AsyncDeliveryDataHelper).GetActiveRecordsfromAsyncQueueTable(tMRN,tAA,tEncNum,.tActiveRecords)
		If (tActiveRecords.AsyncQueueItems.Count()  > 0) {
			Set j = 0
			While (j < tActiveRecords.AsyncQueueItems.Count()) {
				Set tObjectId = tActiveRecords.AsyncQueueItems.GetAt($I(j)).ObjectId
				Set tRequestD=##class(HS.Message.Push.DeliveryRequest).%OpenId(tObjectId)
				
				Set ..HL7Subscription = tActiveRecords.AsyncQueueItems.GetAt(j).Subscription
				Set ..DeliveryOperation = tRequestD.Subscription.DeliveryOperation
				
				$$$LOGINFO("Triggering Subscription: "_..HL7Subscription_" Object ID: "_tObjectId)
				
				Set tSC = ..FetchClinicalBoardData(tActiveRecords,j)
				
				//Fetch SDASubscription from AsyncQueueConfig
				Set tSQL = "select Config.Subscription As SDASubscription, Config.AsyncDigits As AsyncDigits"
				Set tSQL = tSQL_" from CUSTOM_CORE_Table_PushNotification.AsyncQueueConfig Config, CUSTOM_CORE_Table_PushNotification.AsyncQueue Queue" 
				Set tSQL = tSQL_" where Config.CohortInitial = Queue.Cohort AND Config.SubscriptionInitial = ? and Queue.ObjectId = ?"
				Set tResult = ##class(%SQL.Statement).%ExecDirect(, .tSQL,..HL7Subscription, tObjectId)
				If (tResult.%Next()) {					
					//Lace Availability Check, Bit 0 is for Lace
					If ($zboolean(tResult.AsyncDigits,(2**0),1)=(2**0)) {
						If (($zboolean(tActiveRecords.AsyncQueueItems.GetAt(j).AsyncDataDigits,(2**0),1)=(2**0))'=1) {
							$$$LOGINFO("Lace Not Available")
							Continue
						}
					}
									
					//Update Request to SDA Subscription
					Set tRequestD.Subscription.Subject=tResult.SDASubscription
					//+ICIAT-1525
					//$$$THROWONERROR(tSC,..DeliverPushNotification(tRequestD,.tResponseD))
					Set tSC = ..DeliverPushNotification(tRequestD,.tResponseD)
					If $System.Status.IsError(tSC) {
						$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation. Subscription: "_..HL7Subscription_" Object ID: "_tObjectId_" Error Text: "_$System.Status.GetErrorText(tSC))	
						Continue					
					}
					Set tSC = ..UpdateSentTime(tObjectId, ..HL7Subscription)					
					//-ICIAT-1525		
				}				
			}
		}		
	}
	Catch exception {
		Set tSC=exception.AsStatus()
		$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation : "_$System.Status.GetErrorText(tSC))
	}	
	Quit tSC
}

Method DeliverAsyncScheduledPushNotification(pRequest As CUSTOM.Util.Message.ENFrameworkAsyncQueueMonitorServiceRequest, ByRef pResponse As Ens.Response) As %Status
{
	Set tSC=$$$OK
	Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
	Set pResponse.OKToPurge=1
	Try {
		//Get Active Requests (Request for which mail is not yet sent) from Queue table
		Set tActiveRecords = ##class(CUSTOM.Util.Message.FrameworkAsyncQueueResponse).%New()
		Set tSC = ##class(CUSTOM.CORE.Util.AsyncDeliveryDataHelper).GetAllActiveRecordsfromAsyncQueueTable(.tActiveRecords)
		If (tActiveRecords.AsyncQueueItems.Count()  > 0) {
			Set j = 0
			While (j < tActiveRecords.AsyncQueueItems.Count()) {
				Try {
					Set tObjectId = tActiveRecords.AsyncQueueItems.GetAt($I(j)).ObjectId
					Set tInsertTime = tActiveRecords.AsyncQueueItems.GetAt(j).InsertTimeStamp
					Set tDischargeDateTime = tActiveRecords.AsyncQueueItems.GetAt(j).DischargeDateTime
					Set tCurrentTime = $ZDT($H,3)
					Set tRequestD=##class(HS.Message.Push.DeliveryRequest).%OpenId(tObjectId)
					Set ..HL7Subscription = tActiveRecords.AsyncQueueItems.GetAt(j).Subscription
					Set ..DeliveryOperation = tRequestD.Subscription.DeliveryOperation
				
					Set tSC = ..FetchClinicalBoardData(tActiveRecords,j)
				
					//Fetch SDASubscription from AsyncQueueConfig for which SendAfterTimeOut is 1
					Set tSQL = "select Config.Subscription As SDASubscription, Config.ExpirationTime As tExpirationTime"
					Set tSQL = tSQL_" from CUSTOM_CORE_Table_PushNotification.AsyncQueueConfig Config, CUSTOM_CORE_Table_PushNotification.AsyncQueue Queue" 
					Set tSQL = tSQL_" where Config.CohortInitial = Queue.Cohort AND Config.SubscriptionInitial = ? and Queue.ObjectId = ? and Config.SendAfterTimeOut = 1"
					Set tResult = ##class(%SQL.Statement).%ExecDirect(, .tSQL,..HL7Subscription, tObjectId)
					If (tResult.%Next()) {
						Set datediff = $SYSTEM.SQL.DATEDIFF("mi",tInsertTime,tCurrentTime)
						If (datediff > tResult.tExpirationTime) {
							$$$LOGINFO("GetSDAByMRNWithPatientFilter for MRN: "_tActiveRecords.AsyncQueueItems.GetAt(j).MRN_" AA: "_tActiveRecords.AsyncQueueItems.GetAt(j).AssigningAuthority_" EncNum: "_tActiveRecords.AsyncQueueItems.GetAt(j).EncounterNumber)
							set tSDADataHelper = ##class(CUSTOM.CORE.Util.SDADataHelper).%New()
							set tSC = tSDADataHelper.GetSDAByMRNWithPatientFilterExtended(tActiveRecords.AsyncQueueItems.GetAt(j).MRN,tActiveRecords.AsyncQueueItems.GetAt(j).AssigningAuthority,tActiveRecords.AsyncQueueItems.GetAt(j).EncounterNumber,"OBS",1)
							Set Lace = ""
							If $$$ISOK(tSC) {
								Do tSDADataHelper.GetLaceScoreFromSda(.Lace,tDischargeDateTime,.tSC)
								Set ..LaceScoreFromSda = Lace 
								//Update Lace in Clinical Board
								Set tSC = ..UpdateLace(tActiveRecords.AsyncQueueItems.GetAt(j).MRN,tActiveRecords.AsyncQueueItems.GetAt(j).AssigningAuthority,tActiveRecords.AsyncQueueItems.GetAt(j).EncounterNumber,Lace)
							}
							If $$$ISERR(tSC) {
								Set ..LaceScoreFromSda = Lace
								$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation. Error Text: "_$System.Status.GetErrorText(tSC))
							}
				
							$$$LOGINFO("Triggering Subscription: "_..HL7Subscription_" Object ID: "_tObjectId)
							//Update Request to SDA Subscription
							Set tRequestD.Subscription.Subject=tResult.SDASubscription
							//+ICIAT-1525
							//$$$THROWONERROR(tSC,..DeliverPushNotification(tRequestD,.tResponseD))
							Set tSC = ..DeliverPushNotification(tRequestD,.tResponseD)
							If $System.Status.IsError(tSC) {
								$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation. Subscription: "_..HL7Subscription_" Object ID: "_tObjectId_" Error Text: "_$System.Status.GetErrorText(tSC))	
								Continue					
							}
							Set tSC = ..UpdateSentTime(tObjectId, ..HL7Subscription)
							//-ICIAT-1525						
						}
					}
				}
				Catch exception {
					Set tSC=exception.AsStatus()
					$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation : "_$System.Status.GetErrorText(tSC))
				}								
			}
		}		
	}
	Catch exception {
		Set tSC=exception.AsStatus()
		$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation : "_$System.Status.GetErrorText(tSC))
	}	
	Quit tSC
}

Method overrideDataArray(ByRef pDataArray As %String) As %Status
{
	Set pDataArray("SUBSCRIPTIONSUBJECT") = ..HL7Subscription
	If ..LaceScore '="" {
		Set pDataArray("LACESCORE")=..LaceScore
	}
	ElseIf ..LaceScoreFromSda '="" {
		Set pDataArray("LACESCORE")=..LaceScoreFromSda
	}
	If (..DeliveryOperation = "FrameworkApsDeliveryOperation") {
		Set pDataArray("APSLINKWEIGHT")=..RankOrScore
		Set pDataArray("RISKMRN")=..RiskEdgeMRN
		Set pDataArray("RISKASSIGNINGAUTH")=..RiskEdgeAssigningAuthority
		Set pDataArray("FROMTIME")=..FromTime		
	}
	Quit $$$OK
}

Method IsSubscriptionSpecificTrigged(ByRef pDataArray As %String) As %Boolean
{
	Set tStatus=1	
	Try {
		If (..DeliveryOperation = "FrameworkApsDeliveryOperation") {
			Set tStatus=0
			set objEmailContentUtil=##Class(CUSTOM.CORE.Util.EmailContentUtility).%New()
			Set tStatus = objEmailContentUtil.CreateAPSEmailContent(.pDataArray)
		}
	}Catch exception{
		Set tSc=exception.AsStatus()
		set tStatus=0
	}
	Quit tStatus
}

Method IsDeliveryTrigged(pCheckDigits As %Integer, pPatDataArray As %String, pSubscription As HS.Types.SubscriptionSerialInfo) As %Boolean
{
	Quit $$$OK
}

Method UpdateLace(pMRN As %String, pAA As %String, pEncNum As %String, pLace As %String) As %Status
{
	Set tSC=$$$OK
	Try {
		Set pQueueRequest = ##class(CUSTOM.Util.Message.FrameworkAsyncQueueRequest).%New()
		Set pClinicalBoardRequest = ##class(CUSTOM.Util.Message.ClinicalMsgDeliveryBoardRequest).%New()
		Set pQueueRequest.AssigningAuthority = pAA
		Set pQueueRequest.MRN=pMRN
		Set pQueueRequest.EncounterNumber=pEncNum
		Set pClinicalBoardRequest.LACESCORE=pLace
		Set pQueueRequest.ClinicalMsgDeliveryBoard=pClinicalBoardRequest
		
		//Lace: Add 1 to AsyncDataDigit
		Set pQueueRequest.AsyncDataDigits = pQueueRequest.AsyncDataDigits + 1
		
		Set tSC = ##class(CUSTOM.CORE.Util.AsyncDeliveryDataHelper).UpdateAsyncQueue(pQueueRequest)
	}Catch (exception){
		Set tSC=exception.AsStatus()
		$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation:UpdateLace : "_$System.Status.GetErrorText(tSC))		
	}
	Quit tSC
}

Method UpdateSentTime(pObjectId As %String, pSubscription As %String) As %Status
{
	Set tSC=$$$OK
	Try {
		Set tSQL = "Select Id As RowId FROM CUSTOM_CORE_Table_PushNotification.AsyncQueue Where ObjectId = ? AND Subscription = ?"    		
    	Set tResult = ##class(%SQL.Statement).%ExecDirect(, .tSQL, pObjectId, pSubscription)
    	While (tResult.%Next()) { 
    		Set tId = tResult.RowId
			Set request = ##class(CUSTOM.CORE.Table.PushNotification.AsyncQueue).%OpenId(tId)
			Set request.SentTimeStamp=$ZDT($H,3)
			Set tSC = request.%Save()
    	}
	}Catch (exception){
		Set tSC=exception.AsStatus()
		$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation:UpdateSentTime : "_$System.Status.GetErrorText(tSC))		
	}
	Quit tSC
}

Method FetchClinicalBoardData(pActiveRecords As CUSTOM.Util.Message.FrameworkAsyncQueueResponse, j As %Integer) As %Status
{
	Set tSC = $$$OK
	Try {
		Set ..RankOrScore=pActiveRecords.AsyncQueueItems.GetAt(j).ClinicalMsgDeliveryBoard.APSLINKWEIGHT
		Set ..RiskEdgeAssigningAuthority=pActiveRecords.AsyncQueueItems.GetAt(j).ClinicalMsgDeliveryBoard.RISKASSIGNINGAUTH
		Set ..RiskEdgeMRN = pActiveRecords.AsyncQueueItems.GetAt(j).ClinicalMsgDeliveryBoard.RISKMRN
		Set ..FromTime = pActiveRecords.AsyncQueueItems.GetAt(j).ClinicalMsgDeliveryBoard.FROMTIME
		Set ..LaceScore = pActiveRecords.AsyncQueueItems.GetAt(j).ClinicalMsgDeliveryBoard.LACESCORE
	}Catch (exception){
		Set tSC=exception.AsStatus()
		$$$LOGERROR("Error in FrameworkAsyncDeliveryOperation:SetProperties : "_$System.Status.GetErrorText(tSC))		
	}
	Quit tSC
}

}
