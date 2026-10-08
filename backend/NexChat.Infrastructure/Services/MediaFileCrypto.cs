using System.Security.Cryptography;
using Microsoft.Extensions.Logging;

namespace NexChat.Infrastructure.Services;

/// <summary>
/// تشفير ملفات الوسائط عند التخزين على القرص (مفتاح الخادم).
/// الملفات القديمة بلا بادئة تُعاد كما هي. السيرفر ولوحة الإدارة يفكّان التشفير عند التقديم.
/// </summary>
public interface IMediaFileCrypto
{
    bool IsEnabled { get; }
    bool IsEncrypted(ReadOnlySpan<byte> data);
    byte[] Encrypt(byte[] plaintext);
    byte[] Decrypt(byte[] stored);
    Task WriteAllEncryptedAsync(string path, byte[] plaintext, CancellationToken ct = default);
    Task WriteStreamEncryptedAsync(string path, Stream plaintext, CancellationToken ct = default);
    Task<byte[]> ReadAllDecryptedAsync(string path, CancellationToken ct = default);
}

public sealed class MediaFileCrypto : IMediaFileCrypto
{
    /// <summary>ASCII "NC1F" — NexChat file crypto v1.</summary>
    public static ReadOnlySpan<byte> Magic => "NC1F"u8;
    private const int NonceLen = 12;
    private const int TagLen = 16;

    private readonly byte[]? _key;
    private readonly ILogger<MediaFileCrypto>? _logger;

    public MediaFileCrypto(string? secret, ILogger<MediaFileCrypto>? logger = null)
    {
        _logger = logger;
        _key = DeriveKey(secret);
        if (_key == null)
            _logger?.LogWarning("Media file encryption key not set; media stored in plaintext until configured.");
    }

    public bool IsEnabled => _key != null;

    public bool IsEncrypted(ReadOnlySpan<byte> data) =>
        data.Length >= Magic.Length && data[..Magic.Length].SequenceEqual(Magic);

    public byte[] Encrypt(byte[] plaintext)
    {
        if (_key == null || plaintext.Length == 0)
            return plaintext;
        if (IsEncrypted(plaintext))
            return plaintext;

        try
        {
            var nonce = new byte[NonceLen];
            RandomNumberGenerator.Fill(nonce);
            var ciphertext = new byte[plaintext.Length];
            var tag = new byte[TagLen];
            using (var aes = new AesGcm(_key, TagLen))
                aes.Encrypt(nonce, plaintext, ciphertext, tag);

            var combined = new byte[Magic.Length + NonceLen + ciphertext.Length + TagLen];
            Magic.CopyTo(combined);
            Buffer.BlockCopy(nonce, 0, combined, Magic.Length, NonceLen);
            Buffer.BlockCopy(ciphertext, 0, combined, Magic.Length + NonceLen, ciphertext.Length);
            Buffer.BlockCopy(tag, 0, combined, Magic.Length + NonceLen + ciphertext.Length, TagLen);
            return combined;
        }
        catch (Exception ex)
        {
            _logger?.LogError(ex, "Media Encrypt failed; storing plaintext.");
            return plaintext;
        }
    }

    public byte[] Decrypt(byte[] stored)
    {
        if (stored.Length == 0 || _key == null || !IsEncrypted(stored))
            return stored;

        try
        {
            var offset = Magic.Length;
            var nonce = stored.AsSpan(offset, NonceLen);
            var tag = stored.AsSpan(stored.Length - TagLen);
            var ciphertext = stored.AsSpan(offset + NonceLen, stored.Length - offset - NonceLen - TagLen);
            var plaintext = new byte[ciphertext.Length];
            using (var aes = new AesGcm(_key, TagLen))
                aes.Decrypt(nonce, ciphertext, tag, plaintext);
            return plaintext;
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "Media Decrypt failed; returning stored bytes.");
            return stored;
        }
    }

    public async Task WriteAllEncryptedAsync(string path, byte[] plaintext, CancellationToken ct = default)
    {
        var data = Encrypt(plaintext);
        await File.WriteAllBytesAsync(path, data, ct);
    }

    public async Task WriteStreamEncryptedAsync(string path, Stream plaintext, CancellationToken ct = default)
    {
        await using var ms = new MemoryStream();
        if (plaintext.CanSeek) plaintext.Position = 0;
        await plaintext.CopyToAsync(ms, ct);
        await WriteAllEncryptedAsync(path, ms.ToArray(), ct);
    }

    public async Task<byte[]> ReadAllDecryptedAsync(string path, CancellationToken ct = default)
    {
        var stored = await File.ReadAllBytesAsync(path, ct);
        return Decrypt(stored);
    }

    private static byte[]? DeriveKey(string? secret)
    {
        if (string.IsNullOrWhiteSpace(secret))
            return null;
        secret = secret.Trim();
        try
        {
            var bytes = Convert.FromBase64String(secret);
            if (bytes.Length == 32)
                return bytes;
        }
        catch
        {
            // not valid Base64
        }

        return SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(secret));
    }
}
