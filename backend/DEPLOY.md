# نشر NexChat API باستخدام Docker

## البناء والتشغيل

### 1. بناء الصورة
```bash
cd backend
docker build -t nexchat-api .
```

### 2. تشغيل الحاوية
```bash
docker run -d \
  --name nexchat-api \
  -p 4567:4567 \
  -v /www/wwwroot/nexchat-cloud.xaronhost.com/wwwroot:/app/wwwroot \
  -e ConnectionStrings__DefaultConnection="Server=YOUR_DB_HOST;Port=3306;Database=nexchat;User=root;Password=YOUR_PASSWORD;" \
  -e Jwt__Secret="YOUR_JWT_SECRET" \
  --restart unless-stopped \
  nexchat-api
```

### 3. أو باستخدام docker-compose
```bash
cd backend
# عدّل ملف docker-compose.yml (ConnectionString و Jwt__Secret)
docker-compose up -d
```

## المتغيرات المطلوبة
- `ConnectionStrings__DefaultConnection`: سلسلة اتصال MySQL (مثال: Server=localhost;Port=3306;Database=nexchat;User=root;Password=xxx;)
- `Jwt__Secret`: مفتاح JWT السري

## مسار التخزين
الملفات والصور تُخزن في: `/www/wwwroot/nexchat-cloud.xaronhost.com/wwwroot/uploads`

يجب إنشاء المجلد `uploads` داخل المسار أعلاه إذا لم يكن موجوداً:
```bash
mkdir -p /www/wwwroot/nexchat-cloud.xaronhost.com/wwwroot/uploads
chmod 755 /www/wwwroot/nexchat-cloud.xaronhost.com/wwwroot/uploads
```

## المنفذ
التطبيق يعمل على المنفذ **4567**
