Class CUSTOM.CORE.Operation.MessageTcpOperation Extends Ens.BusinessOperation [ ProcedureBlock ]
{

Parameter ADAPTER = "EnsLib.TCP.CountedOutboundAdapter";

/// Name to transmit as the name of the stream content. May include timestamp specifiers. The %f specifier if present will be 
/// replaced with the name of the stream's original source filename (stripped of characters illegal in target filenames).<p>
/// See the method Ens.Util.File.CreateTimestamp() for documentation of timestamping options.<p>
/// If empty, the stream content will be sent as a single counted block without any associated stream name.
Property Streamname As %String(MAXLEN = 1000) [ InitialExpression = "%f" ];

Parameter SETTINGS As %String = "Streamname:Connection";

Method OnMessage(pRequest As Ens.StreamContainer, pResponse As %Persistent) As %Status
{
	Set tSC = $$$OK

	Try {
		//Does not accept a reply from receiving service
		set ..Adapter.GetReply = 0
		
		set tRequest=##class(%GlobalCharacterStream).%New()
		do pRequest.XMLExportToStream(.tRequest)
	
 		Set ^zHealthixStatus = "Export to stream"
		//  Set tSC = ..Adapter.SendMessageStream(pRequest.Stream ,pResponse)
	    //	Set tSC=..Adapter.SendMessageStream(pRequest.Stream,.tReplyStream)  Quit:$$$ISERR(tSC) tSC
		Set tSC=..Adapter.SendMessageStream(tRequest,.tReplyStream)
		Set ^zHealthixStatus = "Export to stream"
		/*
		If ..Adapter.GetReply {
			Set tReply=tReplyStream.Read()
			If $Case(tReply,"":0,"OK":0,:1) {
				Set tSC=$$$ERROR($$$EnsErrGeneral,"Remote acknowledgement not OK:"_$E(tReply,1,1000))
			}
		}
		*/
	}
	Catch eException {
		Set tSC = eException.AsStatus()
		$$$LOGINFO("Error"_$zcvt($system.Status.GetErrorText(tSC),"O","XML"))
	}
		Quit tSC
}

}
