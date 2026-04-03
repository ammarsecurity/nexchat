using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;

namespace NexChat.Infrastructure.Services;

/// <summary>
/// تشفير محتوى رسائل المحادثة عند التخزين (مفتاح الخادم).
/// الرسائل القديمة غير المشفّرة تُعاد كما هي عند فك التشفير.
/// </summary>
public interface IConversationMessageCrypto
{
    string EncryptForStorage(string plaintext);
    string DecryptFromStorage(string stored);
}

public sealed class ConversationMessageCrypto : IConversationMessageCrypto
{
    public const string Prefix = "NC1:";
    private readonly byte[]? _key;
    private readonly ILogger<ConversationMessageCrypto>? _logger;

    public ConversationMessageCrypto(string? secret, ILogger<ConversationMessageCrypto>? logger = null)
    {
        _logger = logger;
        _key = DeriveKey(secret);
        if (_key == null)
            _logger?.LogWarning("Conversation message encryption key not set; messages stored in plaintext until configured.");
    }

    public string EncryptForStorage(string plaintext)
    {
        if (_key == null || string.IsNullOrEmpty(plaintext))
            return plaintext;

        // تجنّب إعادة تشفير بيانات مشفّرة بالفعل (مثلاً بعد ترحيل أو خطأ)
        if (plaintext.StartsWith(Prefix, StringComparison.Ordinal))
            return plaintext;

        try
        {
            var plainBytes = Encoding.UTF8.GetBytes(plaintext);
            var nonce = new byte[12];
            RandomNumberGenerator.Fill(nonce);
            var ciphertext = new byte[plainBytes.Length];
            var tag = new byte[16];
            using (var aes = new AesGcm(_key, tag.Length))
                aes.Encrypt(nonce, plainBytes, ciphertext, tag);

            var combined = new byte[nonce.Length + ciphertext.Length + tag.Length];
            Buffer.BlockCopy(nonce, 0, combined, 0, nonce.Length);
            Buffer.BlockCopy(ciphertext, 0, combined, nonce.Length, ciphertext.Length);
            Buffer.BlockCopy(tag, 0, combined, nonce.Length + ciphertext.Length, tag.Length);

            return Prefix + Convert.ToBase64String(combined);
        }
        catch (Exception ex)
        {
            _logger?.LogError(ex, "EncryptForStorage failed; storing plaintext.");
            return plaintext;
        }
    }

    public string DecryptFromStorage(string stored)
    {
        if (string.IsNullOrEmpty(stored))
            return stored;
        if (_key == null || !stored.StartsWith(Prefix, StringComparison.Ordinal))
            return stored;

        try
        {
            var raw = Convert.FromBase64String(stored[Prefix.Length..]);
            const int nonceLen = 12;
            const int tagLen = 16;
            if (raw.Length < nonceLen + tagLen + 1)
                return stored;

            var nonce = raw.AsSpan(0, nonceLen);
            var tag = raw.AsSpan(raw.Length - tagLen);
            var ciphertext = raw.AsSpan(nonceLen, raw.Length - nonceLen - tagLen);
            var plaintext = new byte[ciphertext.Length];
            using (var aes = new AesGcm(_key, tag.Length))
                aes.Decrypt(nonce, ciphertext, tag, plaintext);
            return Encoding.UTF8.GetString(plaintext);
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "DecryptFromStorage failed; returning stored value as legacy plaintext.");
            return stored;
        }
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
            // ليس Base64 صالحاً
        }

        return SHA256.HashData(Encoding.UTF8.GetBytes(secret));
    }
}
