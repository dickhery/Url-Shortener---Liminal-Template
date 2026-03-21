module {
	/// Exmaple: `("Content-Type", "text/html")`
	public type Header = (Text, Text);

	/// Argument type in `http_request_update`
	public type UpdateRequest = {
		url : Text;
		method : Text;
		headers : [Header];
		body : Blob;
	};

	/// Argument type in `http_request`
	public type Request = UpdateRequest and {
		certificate_version: ?Nat16;
	};

	/// Response type of `http_request_update`
	public type UpdateResponse = {
		status_code : Nat16;
		headers : [Header];
		body : Blob;
		streaming_strategy : ?StreamingStrategy;
	};

	/// Response type of `http_request`
	///
	/// If `upgrade = ?true`, the HTTP Gateway ignores all other fields of the response and performs an update call to `http_request_update`
	public type Response = UpdateResponse and {
		upgrade : ?Bool;
	};

	public type StreamingStrategy = {
		#Callback: {
			callback : StreamingCallback;
			token : StreamingToken;
		};
	};

	/// Use `to_candid` and `from_candid` to convert between the desired type and `Blob`
	public type StreamingToken = Blob;

	public type StreamingCallback = shared query (StreamingToken) -> async ?StreamingCallbackResponse;

	public type StreamingCallbackResponse = {
		body : Blob;
		token : ?StreamingToken;
	};
};