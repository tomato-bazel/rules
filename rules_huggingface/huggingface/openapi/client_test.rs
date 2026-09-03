// Compile + import check for the generated HF Inference Endpoints
// client. No real HTTP — constructing the Client and referencing the
// generated module fails at build time if the codegen pipeline broke.

use inference_endpoints_client::*;

#[test]
fn client_can_be_constructed() {
    // progenitor's Client::new takes a base-URL string; it doesn't
    // open a connection.
    let _client = Client::new("https://api.endpoints.huggingface.cloud");
}
