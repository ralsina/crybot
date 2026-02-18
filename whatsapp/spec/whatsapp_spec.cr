require "spec"
require "../src/whatsapp"

describe WhatsApp do
  describe WhatsApp::Client do
    # TODO: Add tests for the client
    # These would require mocking HTTP requests or using a test token
  end

  describe WhatsApp::Webhook do
    describe "#verify?" do
      it "returns true for valid verification" do
        result = WhatsApp::Webhook.verify?("subscribe", "my_token", "my_token")
        result.should eq(true)
      end

      it "returns false for invalid mode" do
        result = WhatsApp::Webhook.verify?("invalid", "my_token", "my_token")
        result.should eq(false)
      end

      it "returns false for invalid token" do
        result = WhatsApp::Webhook.verify?("subscribe", "wrong_token", "my_token")
        result.should eq(false)
      end
    end

    describe "#valid_signature?" do
      it "verifies valid HMAC signatures" do
        app_secret = "test_secret"
        body = "test_body"

        # Generate a valid signature
        hmac = OpenSSL::HMAC.digest(:sha256, app_secret, body)
        signature = "sha256=#{hmac.hexstring}"

        headers = HTTP::Headers{
          "X-Hub-Signature-256" => signature,
        }

        result = WhatsApp::Webhook.valid_signature?(headers, body, app_secret)
        result.should eq(true)
      end

      it "rejects invalid signatures" do
        headers = HTTP::Headers{
          "X-Hub-Signature-256" => "sha256=invalid",
        }

        result = WhatsApp::Webhook.valid_signature?(headers, "test_body", "test_secret")
        result.should eq(false)
      end

      it "handles missing signature header" do
        headers = HTTP::Headers.new

        result = WhatsApp::Webhook.valid_signature?(headers, "test_body", "test_secret")
        result.should eq(false)
      end
    end
  end
end
