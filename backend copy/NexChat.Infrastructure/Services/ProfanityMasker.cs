using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;

namespace NexChat.Infrastructure.Services;

/// <summary>يستبدل الكلمات المدرجة في الإعدادات بنفس عدد الأحرف برمز النقطة •.</summary>
public interface IProfanityMasker
{
    string Mask(string text);
}

public sealed class ProfanityMasker : IProfanityMasker
{
    private readonly bool _enabled;
    private readonly string[] _words;

    public ProfanityMasker(IConfiguration configuration)
    {
        _enabled = bool.TryParse(configuration["Profanity:Enabled"], out var en) ? en : true;
        _words = configuration.GetSection("Profanity:Words").GetChildren()
            .Select(c => c.Value)
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => x!.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(w => w.Length)
            .ToArray();
    }

    public string Mask(string text)
    {
        if (!_enabled || string.IsNullOrEmpty(text) || _words.Length == 0)
            return text;

        var result = text;
        foreach (var word in _words)
        {
            if (word.Length == 0) continue;
            var escaped = Regex.Escape(word);
            // حدود «كلمة»: ليست جزءاً من سلسلة أحرف/علامات دمج
            var pattern = @"(?<![\p{L}\p{M}])" + escaped + @"(?![\p{L}\p{M}])";
            result = Regex.Replace(
                result,
                pattern,
                m => new string('•', m.Length),
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        return result;
    }
}
