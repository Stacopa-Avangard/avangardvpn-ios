#!/usr/bin/env ruby
# Panggil App Store Connect API pakai kunci .p8 lokal. Tanpa GitHub.
#   ruby asc.rb /v1/users
require 'openssl'; require 'base64'; require 'json'; require 'net/http'

def b64(s)
  Base64.urlsafe_encode64(s).delete('=')
end

key_path = ENV.fetch('ASC_KEY_PATH'); kid = ENV.fetch('ASC_KEY_ID'); iss = ENV.fetch('ASC_ISSUER_ID')
key = OpenSSL::PKey::EC.new(File.read(key_path))

now = Time.now.to_i
header  = { 'alg' => 'ES256', 'kid' => kid, 'typ' => 'JWT' }
payload = { 'iss' => iss, 'iat' => now, 'exp' => now + 600, 'aud' => 'appstoreconnect-v1' }
signing_input = "#{b64(JSON.dump(header))}.#{b64(JSON.dump(payload))}"

# ECDSA di OpenSSL keluar sebagai DER; JWT mau r||s mentah 64 byte.
der  = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
jwt  = "#{signing_input}.#{b64(r + s)}"

# ruby asc.rb <path> [METHOD] [json-body]
path   = ARGV[0] || '/v1/apps'
method = (ARGV[1] || 'GET').upcase
body   = ARGV[2]

uri = URI("https://api.appstoreconnect.apple.com#{path}")
klass = { 'GET' => Net::HTTP::Get, 'PATCH' => Net::HTTP::Patch,
          'POST' => Net::HTTP::Post, 'DELETE' => Net::HTTP::Delete }.fetch(method)

res = Net::HTTP.start(uri.host, 443, :use_ssl => true) do |http|
  req = klass.new(uri, 'Authorization' => "Bearer #{jwt}")
  if body
    req['Content-Type'] = 'application/json'
    req.body = body
  end
  http.request(req)
end
warn "HTTP #{res.code}"
puts res.body
