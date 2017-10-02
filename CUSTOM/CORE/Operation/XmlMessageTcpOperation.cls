Class CUSTOM.CORE.Operation.XmlMessageTcpOperation Extends Ens.BusinessOperation [ ProcedureBlock ]
{

Parameter ADAPTER = "EnsLib.TCP.CountedXMLOutboundAdapter";

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
		Set tSC = ..Adapter.SendMessageXMLObj(pRequest,pResponse)
	}
	Catch eException {
		Set tSC = eException.AsStatus()
		$$$LOGINFO("Error"_$zcvt($system.Status.GetErrorText(tSC),"O","XML"))
	}
	Quit tSC
}

}
