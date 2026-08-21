# ذائقتي — GitHub Pages + Supabase

هذه النسخة أصبحت مرتبطة فعليًا بمشروع Supabase الحالي، وتعمل كمنصة متعددة المستخدمين:

- **مالك المنصة Admin**: Dashboard مركزي لإدارة الحسابات.
- **كل مستخدم**: Dashboard خاص لإضافة المطاعم والكوفيات والأصناف والصور والفواتير.
- **كل مستخدم يملك رابطًا عامًا مستقلًا** يراه الأصدقاء بوضع قراءة فقط.
- **Supabase RLS** يمنع المستخدم من تعديل محتوى مستخدم آخر حتى عند تجاوز واجهة الموقع.

## حالة الربط الحالية

### Supabase — مكتمل

تم ربط `config.js` بالمشروع الحالي باستخدام:

- Project URL العام.
- Publishable Key العام المخصص للمتصفح.

وتم إنشاء:

- `profiles`
- `places`
- `items`
- Storage bucket: `blog-media`
- RLS policies
- Realtime publication
- Trigger لإنشاء Profile تلقائيًا بعد التسجيل

تم تشغيل Supabase Security Advisor بعد الإعداد وكانت النتيجة **0 تحذيرات أمنية**.

### GitHub Pages — بانتظار منح Repository صلاحية للتكامل

حتى يمكن رفع الملفات تلقائيًا من ChatGPT، يجب أن يكون هناك Repository ظاهر لتكامل GitHub.

## الملفات المهمة

- `index.html` — التطبيق.
- `config.js` — بيانات Supabase العامة فقط.
- `supabase-setup.sql` — نسخة مرجعية كاملة لإعداد قاعدة البيانات.
- `.nojekyll` — مناسب للنشر المباشر على GitHub Pages.

## إنشاء حساب المالك Admin

بعد نشر الموقع، أنشئ حسابك بالطريقة العادية من الموقع أولًا. بعد ذلك يمكن ترقية حسابك من SQL Editor بهذا الشكل:

```sql
update public.profiles
set role='admin', is_active=true
where id = (
  select id
  from auth.users
  where email='YOUR_ADMIN_EMAIL'
);
```

استبدل `YOUR_ADMIN_EMAIL` ببريد حساب المالك فقط.

## GitHub Pages

أنشئ Repository مثل:

`thaeeqati`

ثم اجعل تكامل GitHub في ChatGPT يستطيع الوصول إليه. بعد رفع الملفات، فعّل Pages من:

**Settings → Pages → Build and deployment → Deploy from a branch**

واختر:

- Branch: `main`
- Folder: `/ (root)`

## شكل الروابط

الرابط الأساسي سيكون عادة:

`https://USERNAME.github.io/thaeeqati/`

رابط صفحة مستخدم:

`https://USERNAME.github.io/thaeeqati/?u=abdullah`

Dashboard المستخدم:

`https://USERNAME.github.io/thaeeqati/?dashboard=1`

Dashboard المالك:

`https://USERNAME.github.io/thaeeqati/?admin=1`

استخدام Query Parameters متعمد لأنه يعمل بثبات على GitHub Pages بدون Rewrite أو 404.

## Supabase Auth URL Configuration

بعد ظهور رابط GitHub Pages النهائي، حدّث Supabase Authentication → URL Configuration:

- **Site URL** = رابط GitHub Pages الأساسي.
- أضف الرابط الأساسي إلى **Redirect URLs** لتأكيد البريد واسترجاع كلمة المرور.

## الأمان

- لا يوجد `service_role` أو Secret Key في ملفات الواجهة.
- `config.js` يحتوي فقط على Publishable Key، وهو مصمم للاستخدام في المتصفح مع RLS.
- الزائر `anon` لديه SELECT فقط.
- المستخدم المسجل يستطيع كتابة بياناته فقط.
- المستخدم الموقوف لا يستطيع إدارة محتواه حتى يعيد Admin تفعيله.
- الصور تُرفع تحت مجلد يبدأ بـ Auth UID الخاص بصاحب الحساب.
- دوال التفويض الحساسة موجودة داخل schema داخلي غير معروض للـData API.

## Realtime

تمت إضافة الجداول التالية إلى `supabase_realtime`:

- `profiles`
- `places`
- `items`

لذلك التغييرات في التقييمات يمكن أن تظهر مباشرة للصفحات المفتوحة.
