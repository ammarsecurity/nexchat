using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NexChat.API.Services;
using Xunit;

namespace NexChat.Push.Tests;

public class ApnsContractTests
{
    private sealed class Capture : HttpMessageHandler, IHttpClientFactory
    {
        public int Requests;
        public string? Bearer;
        public string? PushType;
        public string? Topic;
        public string? Body;
        public HttpClient CreateClient(string name) => new(this, false);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Requests++;
            Bearer = request.Headers.Authorization?.Parameter;
            PushType = request.Headers.GetValues("apns-push-type").Single();
            Topic = request.Headers.GetValues("apns-topic").Single();
            Body = await request.Content!.ReadAsStringAsync(ct);
            return new(HttpStatusCode.OK);
        }
    }

    [Fact]
    public async Task PUSH02_JwtHasNumericIssuedAtIssuerAndES256AndIsCached()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var path = Path.GetTempFileName();
        try
        {
            await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
            var capture = new Capture();
            var service = new ApnsVoipService(Options.Create(new ApnsVoipOptions {
                KeyPath = path, KeyId = "TESTKEY", TeamId = "TESTTEAM", BundleId = "test.app"
            }), capture, NullLogger<ApnsVoipService>.Instance);
            await service.SendVoipAsync("aabb", new() { ["type"] = "video_call", ["callId"] = Guid.NewGuid().ToString() });
            var token = new JwtSecurityTokenHandler().ReadJwtToken(capture.Bearer);
            Assert.True(key.VerifyData(System.Text.Encoding.ASCII.GetBytes($"{token.RawHeader}.{token.RawPayload}"),
                Microsoft.IdentityModel.Tokens.Base64UrlEncoder.DecodeBytes(token.RawSignature),
                HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
            Assert.Equal("ES256", token.Header.Alg);
            Assert.Equal("TESTKEY", token.Header.Kid);
            Assert.Equal("TESTTEAM", token.Issuer);
            using var payload = JsonDocument.Parse(System.Text.Encoding.UTF8.GetString(
                Microsoft.IdentityModel.Tokens.Base64UrlEncoder.DecodeBytes(token.RawPayload)));
            var iat = payload.RootElement.GetProperty("iat");
            Assert.Equal(JsonValueKind.Number, iat.ValueKind);
            Assert.InRange(iat.GetInt64(), DateTimeOffset.UtcNow.AddMinutes(-1).ToUnixTimeSeconds(), DateTimeOffset.UtcNow.ToUnixTimeSeconds());
            Assert.Equal("voip", capture.PushType);
            Assert.Equal("test.app.voip", capture.Topic);
            var previous = capture.Bearer;
            await service.SendVoipAsync("aabb", new() { ["type"] = "video_call" });
            Assert.Equal(previous, capture.Bearer);
        }
        finally { File.Delete(path); }
    }

    [Theory]
    [InlineData("call_cancel")]
    [InlineData("message")]
    public async Task PUSH04_NonIncomingMessagesNeverUsePushKit(string type)
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var path = Path.GetTempFileName();
        try
        {
            await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
            var capture = new Capture();
            var service = new ApnsVoipService(Options.Create(new ApnsVoipOptions {
                KeyPath = path, KeyId = "TESTKEY", TeamId = "TESTTEAM"
            }), capture, NullLogger<ApnsVoipService>.Instance);
            Assert.True(service.IsConfigured);
            await service.SendVoipAsync("aabb", new() { ["type"] = type });
            Assert.Equal(0, capture.Requests);
        }
        finally { File.Delete(path); }
    }
}
