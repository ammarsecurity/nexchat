using System.Net;
using System.Text.Json;

namespace NexChat.API.Middleware;

public class ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception: {Message}", ex.Message);
            await HandleExceptionAsync(context, ex);
        }
    }

    private static async Task HandleExceptionAsync(HttpContext context, Exception ex)
    {
        context.Response.ContentType = "application/json";
        var (statusCode, message) = ex switch
        {
            UnauthorizedAccessException => (HttpStatusCode.Unauthorized, "غير مصرح"),
            KeyNotFoundException => (HttpStatusCode.NotFound, "المورد غير موجود"),
            ArgumentException => (HttpStatusCode.BadRequest, ex.Message),
            _ => (HttpStatusCode.InternalServerError, "حدث خطأ داخلي")
        };
        context.Response.StatusCode = (int)statusCode;
        var response = new { message };
        await context.Response.WriteAsync(JsonSerializer.Serialize(response));
    }
}
