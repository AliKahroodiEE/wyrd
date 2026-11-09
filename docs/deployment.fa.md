<div dir="rtl">

# استقرار Wyrd برای کاربران واقعی

[English](deployment.md)

این فهرست کارهای صاحب پروژه است برای اجرای Wyrd برای کاربران واقعی با هزینه‌ی **صفر دلار در ماه**.
**هیچ مرحله‌ای کارت بانکی لازم ندارد**: همه‌ی سرویس‌های زیر پلن رایگانی دارند که اصلاً کارت نمی‌خواهد (فقط
[دامنه‌ی شخصی](#custom-domain) که اختیاری است هزینه دارد). مراحل را یک بار به ترتیب انجام بده؛ از آن به بعد هر
push به شاخه‌ی `main` که برنامه یا بک‌اند را تغییر دهد همان را دوباره منتشر می‌کند و هر تگ `v*` یک نسخه‌ی تازه‌ی
اندروید می‌سازد. تغییر یک variable به‌تنهایی چیزی منتشر نمی‌کند: گردش‌کار را دستی اجرا کن.

| بخش | کجا اجرا می‌شود | چطور منتشر می‌شود |
| --- | --- | --- |
| برنامه‌ی وب (همان برنامه‌ی آیفون) | Cloudflare Pages، نشانی `https://wyrd-app.pages.dev` | [`deploy-web.yml`](../.github/workflows/deploy-web.yml) وقتی push به `main` برنامه را تغییر دهد |
| بک‌اند (پایگاه داده، ورود، Edge Functions) | پلن رایگان Supabase | گردش‌کار استقرار بک‌اند ([backend/README.md](../backend/README.md)) |
| برنامه‌ی اندروید | فایل APK امضاشده در GitHub Releases | [`release-android.yml`](../.github/workflows/release-android.yml) با هر تگ `v*` |
| ایمیل‌های ورود | Brevo (یا Gmail) از راه SMTP | SMTP سفارشی Supabase |
| اعلان‌ها (push) | Firebase Cloud Messaging | تابع `notify` در Edge Functions |

کاربران با یک کد ۶ رقمی که برایشان ایمیل می‌شود، با ایمیل و رمز عبور (تأیید ثبت‌نام و بازیابی رمز هم با کد ۶ رقمی
است)، یا با گوگل یا گیت‌هاب وارد می‌شوند.

نشانی عمومی سایت فقط در **یک** جا تعریف می‌شود: متغیر مخزن گیت‌هاب به نام `WYRD_SITE_URL`. هر
چیزی که به این نشانی نیاز دارد (ساخت نسخه‌ی وب، فایل APK و تنظیمات بازگشت Supabase) آن را از همین
متغیر می‌خواند؛ پس رفتن به دامنه‌ی شخصی در آینده کار کوتاهی است ([دامنه‌ی شخصی در آینده](#custom-domain)).

## سقف پلن‌های رایگان

| سرویس | سهمیه‌ی رایگان | حواست باشد |
| --- | --- | --- |
| Supabase | ۵۰۰ مگابایت پایگاه داده، ۵ گیگابایت ترافیک خروجی در ماه، ۵۰٬۰۰۰ کاربر فعال ماهانه، ۱ گیگابایت فضای فایل، ۵۰۰٬۰۰۰ اجرای Edge Function در ماه | پروژه **بعد از ۷ روز بدون فعالیت پایگاه داده متوقف می‌شود** (از داشبورد دوباره راهش بینداز). **پشتیبان‌گیری خودکار ندارد**؛ مرحله‌ی ۷ برای همین است. |
| Cloudflare Pages | درخواست‌ها و پهنای باند فایل‌های ایستا نامحدود | حداکثر ۲۰٬۰۰۰ فایل در هر استقرار و ۲۵ مبی‌بایت برای هر فایل (خروجی وب خیلی کمتر از این است). |
| Brevo | ۳۰۰ ایمیل در روز | نشانی فرستنده باید تأیید شود؛ بدون دامنه‌ی شخصی بعضی ایمیل‌ها به هرزنامه می‌روند. |
| Gmail (جایگزین) | حدود ۵۰۰ ایمیل در روز | تأیید دومرحله‌ای و یک app password لازم است. |
| Resend (بعداً، با دامنه‌ی شخصی) | ۳٬۰۰۰ ایمیل در ماه، ۱۰۰ در روز | باید رکوردهای DNS دامنه‌ات را تنظیم کنی. |
| Firebase Cloud Messaging | رایگان در پلن Spark | روی Spark بمان: Blaze تنها پلن Firebase است که کارت می‌خواهد و اعلان‌ها به آن نیازی ندارند. |
| GitHub | Actions برای مخزن عمومی رایگان است، Releases رایگان است | مخزن خصوصی ماهانه ۲٬۰۰۰ دقیقه Actions دارد. |

## چه چیزهایی لازم داری

هفت چیز، همه رایگان و هیچ‌کدام کارت بانکی نمی‌خواهد:

1. **Supabase**: حسابی برای پروژه‌ی بک‌اند (مرحله‌ی ۱).
2. **Cloudflare**: حسابی برای میزبانی نسخه‌ی وب (مرحله‌ی ۲).
3. **Brevo یا یک app password در Gmail**: فرستنده‌ی ایمیل‌های ورود (مرحله‌ی ۳).
4. **Firebase**: پروژه‌ای برای اعلان‌ها (مرحله‌ی ۴).
5. **یک OAuth client در گوگل و یک OAuth app در گیت‌هاب**: برای دکمه‌های «ادامه با گوگل» و «ادامه با
   گیت‌هاب» (مرحله‌ی ۵). ممکن است Google Cloud یک دوره‌ی آزمایشی رایگان پیشنهاد کند که کارت می‌خواهد:
   ردش کن، ساختن client ورود به حساب پرداخت نیازی ندارد.
6. **یک keystore اندروید**: کلیدی که APK را امضا می‌کند (مرحله‌ی ۶). اسکریپت راه‌اندازی آن را با `keytool`
   می‌سازد که همراه هر JDK هست (Android Studio هم یکی دارد).
7. **age** برای پشتیبان‌گیری: پشتیبان‌های پایگاه داده را رمز می‌کند (مرحله‌ی ۷). نصبش: `brew install age`،
   `sudo apt install age` یا `winget install FiloSottile.age`.

مقدارهای مرحله‌های ۱ تا ۵ را جمع کن و بعد `tool/setup_production.sh` را اجرا کن (مرحله‌ی ۸): همه را در
گیت‌هاب ذخیره می‌کند و اگر هنوز keystore اندروید و کلید age نداری، آن‌ها را هم می‌سازد. نام‌هایی که به شکل
`code` آمده‌اند، نام secret (خصوصی) یا variable (تنظیم عمومی برنامه) در گیت‌هاب هستند و اسکریپت تک‌تک‌شان را
می‌پرسد. یک مدیر رمز عبور دم دست داشته باش؛ بعضی از مقدارها فقط یک بار نشان داده می‌شوند.

## ۱. پروژه‌ی Supabase

1. پروژه را در <https://supabase.com/dashboard/new> با پلن **Free** بساز: نام `wyrd`، یک **رمز پایگاه داده‌ی**
   بلند و تصادفی (نگهش دار: `SUPABASE_DB_PASSWORD`) و **نزدیک‌ترین منطقه به بیشتر کاربرانت** (برای اروپا و
   خاورمیانه، فرانکفورت انتخاب خوبی است). پلن رایگان دو پروژه‌ی فعال را اجازه می‌دهد.
2. **شناسه‌ی پروژه (ref)** همان بخش آخر نشانی داشبورد است، یعنی
   `https://supabase.com/dashboard/project/<ref>`: این می‌شود `SUPABASE_PROJECT_ID`. **نشانی پروژه**
   `https://<ref>.supabase.co` است: `SUPABASE_URL`.
3. کلیدهای API در <https://supabase.com/dashboard/project/_/settings/api-keys> (پروژه‌های تازه دیگر کلیدهای
   قدیمی `anon` و `service_role` ندارند):
   - **کلید publishable** (`sb_publishable_…`) داخل برنامه‌ها می‌رود: `SUPABASE_PUBLISHABLE_KEY`.
   - در بخش **Secret keys** یک secret key تازه با نام `github-deploy` بساز و کپی‌اش کن (`sb_secret_…`):
     `SUPABASE_SECRET_KEY`. استقرار بک‌اند آن را در Vault پایگاه داده نگه می‌دارد تا کارهای زمان‌بندی‌شده و
     triggerهای پایگاه داده بتوانند Edge Functions را صدا بزنند. این کلید از row-level security رد می‌شود: مثل
     رمز عبور با آن رفتار کن و هیچ‌وقت داخل build برنامه نگذارش. خود Edge Functions کلیدهایشان را خودکار از
     Supabase می‌گیرند.
4. توکن دسترسی شخصی برای استقرار بک‌اند، در <https://supabase.com/dashboard/account/tokens>:
   **Generate new token**، که می‌شود `SUPABASE_ACCESS_TOKEN`.
5. اگر رمز پایگاه داده را گم کردی، در <https://supabase.com/dashboard/project/_/database/settings>
   عوضش کن.

لازم نیست چیز دیگری را در داشبورد تنظیم کنی: روش‌های ورود، نشانی‌های بازگشت، SMTP و قالب ایمیل‌ها
از `backend/supabase/config.toml` می‌آیند و استقرار بک‌اند آن‌ها را اعمال می‌کند. در پروژه‌های تازه
جدول‌ها خودکار در Data API در دسترس نیستند؛ migrationها دقیقاً همان دسترسی‌هایی را می‌دهند که برنامه
لازم دارد.

## ۲. حساب Cloudflare

1. در <https://dash.cloudflare.com/sign-up> ثبت‌نام کن (پلن رایگان، کارت بانکی لازم نیست).
2. **Account ID**: صفحه‌ی <https://dash.cloudflare.com/?to=/:account/workers-and-pages> را باز کن و
   Account ID را از ستون کناری کپی کن: `CLOUDFLARE_ACCOUNT_ID`.
3. **توکن API**: در <https://dash.cloudflare.com/profile/api-tokens> روی **Create Token** و بعد
   **Create Custom Token** بزن. دسترسی: *Account* · *Cloudflare Pages* · *Edit*. منابع حساب:
   *Include* · حساب خودت. نگهش دار: `CLOUDFLARE_API_TOKEN`.
4. نام پروژه‌ی Pages: `wyrd-app` (نام `wyrd` گرفته شده): `CF_PAGES_PROJECT`. لازم نیست خودت
   بسازی‌اش؛ اولین استقرار آن را می‌سازد. اگر نشانی `pages.dev` آن هم گرفته شده باشد، Cloudflare یک پسوند
   اضافه می‌کند (`wyrd-app-abc.pages.dev`): اولین استقرار وب هشدار می‌دهد و باید `WYRD_SITE_URL` را همان
   نشانی بگذاری.

## ۳. فرستنده‌ی ایمیل

کدهای ورود، تأیید ثبت‌نام و بازیابی رمز همه کدهای ۶ رقمی‌اند که با ایمیل فرستاده می‌شوند. فرستنده‌ی
داخلی Supabase فقط به اعضای تیم خودت در Supabase ایمیل می‌دهد (ساعتی ۲ تا)، پس برای کاربران واقعی یک
حساب SMTP جدا لازم است (SMTP سفارشی در پلن رایگان هم مجاز است). یکی را انتخاب کن:

**Brevo (پیشنهاد فعلی).** رایگان، روزی ۳۰۰ ایمیل، بدون نیاز به دامنه و کارت بانکی.

1. در <https://www.brevo.com> ثبت‌نام کن.
2. نشانی فرستنده (صندوقی که مال خودت است) را اضافه و تأیید کن:
   <https://app.brevo.com/senders/list>. این می‌شود `SMTP_ADMIN_EMAIL`.
3. تنظیمات SMTP در <https://app.brevo.com/settings/keys/smtp>: سرور `smtp-relay.brevo.com`
   (`SMTP_HOST`)، درگاه `587` (`SMTP_PORT`)، **login** که همان‌جا نشان داده می‌شود و شبیه
   `…@smtp-brevo.com` است (`SMTP_USER`) و یک **SMTP key** تازه (`SMTP_PASS`).

**Gmail.** از یک نشانی Gmail که همین حالا داری استفاده می‌کند؛ حدود ۵۰۰ ایمیل در روز.

1. تأیید دومرحله‌ای را روشن کن: <https://myaccount.google.com/signinoptions/twosv>.
2. یک app password به نام `Wyrd` بساز: <https://myaccount.google.com/apppasswords> (۱۶ حرف،
   `SMTP_PASS`).
3. سرور `smtp.gmail.com`، درگاه `587`، نام کاربری و فرستنده همان نشانی Gmail توست.

نام فرستنده (`SMTP_SENDER_NAME`) همان `Wyrd` است. تا وقتی دامنه‌ی شخصی نداری، از آزمایش‌کننده‌ها
بخواه بار اول پوشه‌ی هرزنامه را هم نگاه کنند. وقتی دامنه گرفتی، به Resend برو
([دامنه‌ی شخصی در آینده](#custom-domain)).

## ۴. Firebase (اعلان‌ها)

1. در <https://console.firebase.google.com> روی **Create a project** بزن و نامش را `wyrd` بگذار. Google
   Analytics لازم نیست. پروژه‌های تازه روی پلن رایگان **Spark** هستند که Cloud Messaging را دارد؛ به Blaze
   ارتقا نده.
2. **برنامه‌ی وب**: در Project settings بخش *Your apps* یک برنامه‌ی وب (`</>`) با نام `Wyrd` و بدون
   Hosting اضافه کن. از تنظیماتی که نشان می‌دهد: `apiKey` می‌شود `FIREBASE_API_KEY`، `appId` می‌شود
   `FIREBASE_APP_ID_WEB`، `messagingSenderId` می‌شود `FIREBASE_MESSAGING_SENDER_ID` و `projectId`
   می‌شود `FIREBASE_PROJECT_ID`.
3. **برنامه‌ی اندروید**: یک برنامه‌ی اندروید با package name برابر `app.wyrd` اضافه کن و فیلد اختیاری اثر
   انگشت گواهی را خالی بگذار (اعلان‌ها به آن نیازی ندارند). App ID آن (`1:…:android:…`) می‌شود
   `FIREBASE_APP_ID_ANDROID`. برنامه هنگام ساخت از همین مقدارها تنظیم می‌شود؛ فایل `google-services.json`
   لازم نیست (و بیرون از git می‌ماند).
4. **کلید web push**: در <https://console.firebase.google.com/project/_/settings/cloudmessaging>
   بخش *Web configuration* روی **Generate key pair** بزن. کلید عمومی می‌شود `FIREBASE_VAPID_KEY`.
5. **کلید سرور** برای تابع `notify`: در
   <https://console.firebase.google.com/project/_/settings/serviceaccounts/adminsdk> روی
   **Generate new private key** بزن. فایل JSON دانلودشده را بیرون از مخزن نگه دار؛ اسکریپت آن را در
   `FCM_SERVICE_ACCOUNT` می‌ریزد و بعد می‌توانی پاکش کنی.

مقدارهای تنظیم وب Firebase ذاتاً عمومی‌اند؛ فقط کلید service account محرمانه است.

## ۵. ورود با گوگل و گیت‌هاب

هر دو، کاربر را به یک نشانی بازگشت در Supabase می‌فرستند:
`https://<ref>.supabase.co/auth/v1/callback`. بعد در وب، ورود به `WYRD_SITE_URL` برمی‌گردد و گوشی‌ها از راه
`app.wyrd://auth-callback` به برنامه برمی‌گردند؛ تنظیمات بک‌اند هر دو را مجاز می‌کند.

**گوگل.** در [Google Cloud console](https://console.cloud.google.com)، با پروژه‌ای که Firebase ساخته (یا یک
پروژه‌ی تازه؛ حساب پرداخت لازم نیست):

1. **Google Auth Platform → Branding** (<https://console.cloud.google.com/auth/branding>): نام برنامه
   `Wyrd`، ایمیل پشتیبانی‌ات و صفحه‌های برنامه: صفحه‌ی اصلی `WYRD_SITE_URL`، حریم خصوصی
   `WYRD_SITE_URL/privacy` و شرایط استفاده `WYRD_SITE_URL/terms` (هر دو صفحه همراه نسخه‌ی وب منتشر
   می‌شوند؛ اگر تنظیمات تو فرق دارد `app/web/privacy.html` و `app/web/terms.html` را ویرایش کن). لوگو
   بارگذاری نکن: با لوگو، گوگل تأیید برنامه را الزامی می‌کند.
2. **Audience**: گزینه‌ی *External* و بعد **Publish app** (فقط دسترسی‌های پایه‌ی ایمیل و پروفایل استفاده
   می‌شوند، پس بازبینی لازم نیست).
3. **Clients → Create client** → *Web application* با نام `Wyrd web (Supabase)`. در Authorized JavaScript
   origins نشانی `WYRD_SITE_URL` و در Authorized redirect URIs نشانی
   `https://<ref>.supabase.co/auth/v1/callback` را بگذار.
4. **client ID** (`WYRD_GOOGLE_CLIENT_ID`) و **client secret** (`WYRD_GOOGLE_CLIENT_SECRET`) را کپی کن.
   secret فقط یک بار نشان داده می‌شود؛ اگر گمش کردی، client را باز کن، **Add secret** را بزن و قبلی را
   پاک کن.

تا وقتی هویت برنامه تأیید نشده (که دامنه‌ی شخصی لازم دارد)، صفحه‌ی رضایت گوگل به‌جای Wyrd نام
`<ref>.supabase.co` را نشان می‌دهد. ورود همان‌طور کار می‌کند.

**گیت‌هاب.**

1. یک OAuth app تازه بساز: <https://github.com/settings/applications/new> (یک *OAuth App*، نه
   GitHub App).
   - نام برنامه `Wyrd` و homepage URL برابر `WYRD_SITE_URL`.
   - Authorization callback URL: `https://<ref>.supabase.co/auth/v1/callback`.
2. روی **Generate a new client secret** بزن. client ID و secret را کپی کن.

گیت‌هاب اجازه نمی‌دهد نام secret یا variable با `GITHUB_` شروع شود، پس این‌ها با نام
`WYRD_GITHUB_CLIENT_ID` (variable) و `WYRD_GITHUB_CLIENT_SECRET` (secret) ذخیره می‌شوند.

مقدارهای `WYRD_AUTH_GOOGLE=true` و `WYRD_AUTH_GITHUB=true` این دو را روشن می‌کنند. هر دکمه فقط وقتی
نشان داده می‌شود که کلیدش روشن باشد و client ID و secret آن هر دو ذخیره شده باشند، پس دکمه‌ی نیمه‌کاره
هیچ‌وقت دیده نمی‌شود.

## ۶. کلید امضای اندروید

فایل APK باید برای همیشه با یک کلید امضا شود: اندروید فقط وقتی به‌روزرسانی را روی برنامه‌ی نصب‌شده
می‌نشاند که امضاها یکی باشند. اسکریپت راه‌اندازی کلید را با `keytool` می‌سازد (RSA با طول ۴۰۹۶ بیت، معتبر
برای ۲۷ سال)، اثر انگشت SHA-256 آن را چاپ می‌کند (یادداشت هر نسخه هم آن را نشان می‌دهد تا هر کسی بتواند ببیند
APK مال توست) و آن را با نام‌های `ANDROID_KEYSTORE_BASE64`، `ANDROID_KEYSTORE_PASSWORD`، `ANDROID_KEY_ALIAS` و
`ANDROID_KEY_PASSWORD` در گیت‌هاب ذخیره می‌کند.

**از فایل keystore و رمزش نسخه‌ی پشتیبان بگیر.** اگر گم شوند، کاربران فقط بعد از حذف نسخه‌ی قبلی
می‌توانند نسخه‌ی تازه را نصب کنند و داده‌های محلی‌شان پاک می‌شود.

برای امضای نسخه‌ی انتشار روی کامپیوتر خودت، `app/android/key.properties.example` را به
`app/android/key.properties` کپی کن (در git نادیده گرفته می‌شود) و پرش کن. بدون آن، نسخه‌های انتشار
محلی با کلید debug امضا می‌شوند.

## ۷. پشتیبان‌گیری

پروژه‌های رایگان Supabase پشتیبان خودکار ندارند. یک پشتیبان کامل سه خروجی از پایگاه داده است: نقش‌ها
(roles)، ساختار (schema) و داده‌ها. پشتیبان‌ها برای یک کلید [age](https://github.com/FiloSottile/age) رمز
می‌شوند، پس هر جایی می‌شود نگهشان داشت و فقط خودت می‌توانی بازشان کنی. اسکریپت راه‌اندازی می‌تواند کلید را
بسازد، یا خودت دستی:

<div dir="ltr">

```bash
mkdir -p ~/.config/wyrd
age-keygen -o ~/.config/wyrd/wyrd-backup-key.txt   # prints "Public key: age1…"
```

</div>

- کلید عمومی (`age1…`) می‌شود `BACKUP_AGE_RECIPIENT` (یک variable؛ فقط می‌تواند رمز کند).
- فایل کلید تنها راه باز کردن پشتیبان‌هاست. یک نسخه از آن را در مدیر رمز عبور یا جای آفلاین دیگری
  نگه دار. هیچ‌وقت commitاش نکن و در گیت‌هاب نگذارش.
- برای خواندن یک پشتیبان:

<div dir="ltr">

```bash
age --decrypt -i ~/.config/wyrd/wyrd-backup-key.txt <file>.age > <file>
```

</div>

## ۸. ذخیره‌ی همه‌چیز در گیت‌هاب

از داخل مخزن، با [GitHub CLI](https://cli.github.com) و دسترسی مدیر روی مخزن:

<div dir="ltr">

```bash
gh auth login                    # once
tool/setup_production.sh         # or: tool/setup_production.sh --repo OWNER/REPO
```

</div>

اسکریپت گروه‌های بالا را به همین ترتیب یکی‌یکی می‌پرسد، اجازه می‌دهد هر کدام را رد کنی و هر وقت خواستی
می‌شود دوباره اجرایش کرد: گروه‌هایی که کامل‌اند رد می‌شوند مگر بخواهی عوضشان کنی، و Enter مقدار ذخیره‌شده را
نگه می‌دارد. رمزها، توکن‌ها و کلیدها هنگام تایپ نمایش
داده نمی‌شوند و از راه stdin به `gh` می‌رسند. نتیجه را در
`https://github.com/OWNER/REPO/settings/secrets/actions` (زبانه‌های secrets و variables) ببین.

| نام | نوع | چه کسی استفاده می‌کند |
| --- | --- | --- |
| `SUPABASE_URL`، `SUPABASE_PUBLISHABLE_KEY` | variable | ساخت نسخه‌ی وب و اندروید |
| `SUPABASE_PROJECT_ID`، `SUPABASE_ACCESS_TOKEN`، `SUPABASE_DB_PASSWORD` | secret | استقرار بک‌اند، پشتیبان‌گیری |
| `SUPABASE_SECRET_KEY` | secret | استقرار بک‌اند (در Vault پایگاه داده نگه داشته می‌شود) |
| `WYRD_SITE_URL` | variable | هر چیزی که نشانی عمومی را لازم دارد |
| `CLOUDFLARE_API_TOKEN`، `CLOUDFLARE_ACCOUNT_ID` | secret | استقرار وب |
| `CF_PAGES_PROJECT` | variable | استقرار وب (پیش‌فرض `wyrd-app`) |
| `SMTP_HOST`، `SMTP_PORT`، `SMTP_USER`، `SMTP_PASS`، `SMTP_ADMIN_EMAIL`، `SMTP_SENDER_NAME` | secret | استقرار بک‌اند (SMTP سفارشی Supabase) |
| `FIREBASE_API_KEY`، `FIREBASE_APP_ID_WEB`، `FIREBASE_APP_ID_ANDROID`، `FIREBASE_MESSAGING_SENDER_ID`، `FIREBASE_PROJECT_ID`، `FIREBASE_VAPID_KEY` | variable | ساخت برنامه |
| `FCM_SERVICE_ACCOUNT` | secret | استقرار بک‌اند (تابع `notify`) |
| `WYRD_GOOGLE_CLIENT_ID` / `WYRD_GOOGLE_CLIENT_SECRET` | variable / secret | استقرار بک‌اند، ساخت برنامه (نمایش دکمه) |
| `WYRD_AUTH_GOOGLE` | variable | ساخت برنامه و استقرار بک‌اند (`true` ورود با گوگل را روشن می‌کند) |
| `WYRD_GITHUB_CLIENT_ID` / `WYRD_GITHUB_CLIENT_SECRET` | variable / secret | استقرار بک‌اند، ساخت برنامه (نمایش دکمه) |
| `WYRD_AUTH_GITHUB` | variable | ساخت برنامه و استقرار بک‌اند (`true` ورود با گیت‌هاب را روشن می‌کند) |
| `ANDROID_KEYSTORE_BASE64`، `ANDROID_KEYSTORE_PASSWORD`، `ANDROID_KEY_ALIAS`، `ANDROID_KEY_PASSWORD` | secret | انتشار اندروید |
| `BACKUP_AGE_RECIPIENT` | variable | پشتیبان‌گیری |

## ۹. اولین استقرار

ترتیب مهم است: برنامه‌ها به بک‌اند نیاز دارند.

1. **بک‌اند.** گردش‌کار استقرار بک‌اند را از زبانه‌ی **Actions** مخزن اجرا کن (یا به `main` push
   کن). این گردش‌کار migrationها، تنظیمات ورود و ایمیل و Edge Functions را اعمال می‌کند. بعد
   <https://supabase.com/dashboard/project/_/auth/url-configuration> را نگاه کن: Site URL باید همان
   `WYRD_SITE_URL` باشد و فهرست نشانی‌های بازگشت هم آن و هم `app.wyrd://auth-callback` را داشته باشد.
2. **وب.** در **Actions** گردش‌کار **Deploy web (Cloudflare Pages)** را با **Run workflow** اجرا کن،
   یا `gh workflow run deploy-web.yml`. اجرای اول پروژه‌ی Pages را می‌سازد. `https://wyrd-app.pages.dev`
   را باز کن، با کد ایمیلی حساب بساز و یک حساب با رمز عبور و ورود با گوگل و گیت‌هاب را هم امتحان کن.
3. **اندروید.** اولین نسخه را تگ بزن:

<div dir="ltr">

```bash
git tag v1.0.0
git push origin v1.0.0
```

</div>

گردش‌کار **Release Android APK** فایل `wyrd-1.0.0.apk` را می‌سازد، بررسی می‌کند که با کلید انتشار
خودت امضا شده باشد و GitHub Release را با راهنمای نصب منتشر می‌کند. تگ نسخه را تعیین می‌کند (`v1.4.2`
یعنی 1.4.2)؛ مقدار `version:` در `app/pubspec.yaml` را هم هماهنگ نگه دار تا هشدار نگیری.

از این به بعد: هر push به `main` که `app/` یا `packages/` را تغییر دهد نسخه‌ی وب را دوباره منتشر می‌کند
و هر تگ تازه یک APK می‌سازد. اگر `CLOUDFLARE_API_TOKEN` تنظیم نشده باشد، گردش‌کار وب به‌جای خطا فقط
با یک پیام رد می‌شود.

## کاربران چطور Wyrd را نصب می‌کنند

- **هر مرورگری:** `https://wyrd-app.pages.dev` را باز کنند. Chrome و Edge روی دسکتاپ گزینه‌ی
  **Install** را در نوار نشانی نشان می‌دهند.
- **آیفون و آیپد (iOS 16.4 یا جدیدتر):** سایت را در Safari باز کنند، **Share** را بزنند (در iOS 26 ممکن است
  زیر دکمه‌ی **•••** باشد)، بعد **Add to Home Screen** را انتخاب کنند، گزینه‌ی **Open as Web App** را
  روشن بگذارند و Wyrd را از صفحه‌ی اصلی باز کنند. اعلان‌ها فقط در همین برنامه‌ی صفحه‌ی اصلی کار
  می‌کنند، بعد از این‌که وقتی برنامه اجازه خواست قبول کنند. تا آن موقع برنامه این راهنما را در تنظیمات، بخش
  ظاهر، نشان می‌دهد (می‌شود بستش).
- **اندروید:** [Obtainium](https://obtainium.imranr.dev) را نصب کنند و `https://github.com/OWNER/REPO`
  را اضافه کنند. Obtainium فایل APK را از GitHub Releases نصب می‌کند و هر به‌روزرسانی را پیشنهاد
  می‌دهد. یا فایل `wyrd-x.y.z.apk` را از صفحه‌ی Releases دانلود کنند، بازش کنند و به مرورگر اجازه‌ی نصب
  برنامه بدهند. ممکن است Play Protect تأیید بخواهد (*More details* و بعد *Install anyway*). اعلان‌ها در
  این APK هم کار می‌کنند.

گوگل در حال اجرای «تأیید توسعه‌دهنده» برای برنامه‌هایی است که بیرون از Play Store نصب می‌شوند (از
سپتامبر ۲۰۲۶ در چند کشور اجباری شده و از ۲۰۲۷ کشورهای بیشتری). پیش از این‌که به کشور کاربرانت برسد،
شرایط فعلی را در <https://developer.android.com/developer-verification> ببین.

<a id="custom-domain"></a>

## دامنه‌ی شخصی در آینده

نشانی `https://wyrd-app.pages.dev` می‌تواند برای همیشه بماند. دامنه‌ی شخصی اختیاری است و تنها چیزی در این
راهنماست که هزینه دارد (یک دامنه‌ی `.com` حدود ۱۰ دلار در سال)؛ بقیه‌ی چیزها رایگان می‌مانند.

1. یک دامنه بگیر (Cloudflare Registrar به قیمت تمام‌شده می‌فروشد:
   <https://dash.cloudflare.com/?to=/:account/domains/register>).
2. در Cloudflare بخش Workers & Pages، پروژه‌ی `wyrd-app`، **Custom domains** و بعد **Set up a custom
   domain**. اگر دامنه روی Cloudflare باشد، رکورد DNS خودکار ساخته می‌شود.
3. همه‌چیز را با یک تغییر به آن نشانی ببر: `gh variable set WYRD_SITE_URL --body https://your.domain` (یا
   گروه *Site address* در اسکریپت راه‌اندازی).
4. گوگل: در Google Auth Platform پیوندهای صفحه‌ی اصلی، حریم خصوصی و شرایط (Branding) و JavaScript origin
   مربوط به client را به نشانی تازه تغییر بده. در OAuth app گیت‌هاب، homepage URL را عوض کن. نشانی callback
   (`https://<ref>.supabase.co/auth/v1/callback`) برای هیچ‌کدام عوض نمی‌شود.
5. ایمیل: دامنه را در <https://resend.com/domains> اضافه کن، رکوردهای DNSی را که نشان می‌دهد در DNS
   کلادفلر بساز و صبر کن تا *Verified* شود. در <https://resend.com/api-keys> یک API key بساز و بعد
   گروه ایمیل اسکریپت راه‌اندازی را با گزینه‌ی *Resend* دوباره اجرا کن: سرور `smtp.resend.com`، درگاه
   `587`، کاربر `resend`، API key به‌عنوان رمز و فرستنده `no-reply@your.domain`.
6. دوباره منتشر کن: اول بک‌اند (Site URL، فهرست نشانی‌های بازگشت، SMTP)، بعد نسخه‌ی وب (**Run workflow**).
   نسخه‌ی بعدی اندروید نشانی تازه را می‌گیرد؛ ورود در گوشی به آن وابسته نیست.

نشانی `pages.dev` همچنان کار می‌کند، اما ورود با گوگل و گیت‌هاب فقط به نشانی تازه برمی‌گردد، پس همان را به بقیه بده.
برنامه‌های صفحه‌ی اصلی آیفون به نشانی‌ای وابسته‌اند که از آن اضافه شده‌اند، پس از کاربران آیفون بخواه یک بار
نشانی تازه را اضافه کنند (داده‌های همگام‌شده‌شان بعد از ورود برمی‌گردد).

## اگر چیزی درست کار نکرد

- **گردش‌کار وب می‌گوید «skipped»:** `CLOUDFLARE_API_TOKEN` تنظیم نشده؛ اسکریپت راه‌اندازی را اجرا کن.
- **ایمیلی نمی‌رسد:** ببین فرستنده نزد سرویس‌دهنده تأیید شده باشد، لاگ‌های Auth در Supabase و پوشه‌ی
  هرزنامه را نگاه کن.
- **ورود با گوگل یا گیت‌هاب خطا می‌دهد:** نشانی بازگشت باید `https://<ref>.supabase.co/auth/v1/callback`
  باشد (در گوگل، خطای *redirect_uri_mismatch* یعنی این نشانی در redirect URIهای client نیست) و استقرار
  بک‌اند باید بعد از ذخیره‌ی client ID، secret و `WYRD_AUTH_GOOGLE=true` / `WYRD_AUTH_GITHUB=true` اجرا شده
  باشد. پیام *Access blocked: app not published* در گوگل یعنی صفحه‌ی Audience هنوز *Testing* است.
- **دکمه‌ی گوگل یا گیت‌هاب دیده نمی‌شود:** کلید روشن‌کردن، client ID یا secret آن کم است؛ استقرار وب
  هشداری با نام همان مورد نشان می‌دهد. ذخیره‌اش کن و نسخه‌ی وب را دوباره منتشر کن.
- **بعد از یک هفته‌ی بی‌فعالیت برنامه به بک‌اند وصل نمی‌شود:** پروژه‌ی رایگان متوقف شده؛ از داشبورد
  Supabase دوباره راهش بینداز.
- **گردش‌کار انتشار در «Check signing secrets» شکست می‌خورد:** مرحله‌ی اندروید اسکریپت راه‌اندازی را
  اجرا کن.

</div>
