// Supabase frontend configuration.
// Publishable keys are designed for browser use when RLS is enabled.
// Never place a service_role or secret key in this file.
window.APP_CONFIG = {
  SUPABASE_URL: 'https://itcbahydyqhlybofcyuh.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_qL-6DKVkAc3XWJ7JH-p2_A_-8myYRgp'
};

// Auth UX patch v1.1: allow username OR email without exposing user emails.
window.addEventListener('DOMContentLoaded', () => {
  const cfg = window.APP_CONFIG;
  const input = document.getElementById('loginEmail');
  const passwordInput = document.getElementById('loginPassword');
  const loginBtn = document.getElementById('loginBtn');
  if (!cfg || !input || !passwordInput || !loginBtn || !window.supabase) return;

  const field = input.closest('.field');
  const label = field?.querySelector('label');
  if (label) label.textContent = 'اسم المستخدم أو البريد الإلكتروني';
  input.type = 'text';
  input.setAttribute('dir', 'ltr');
  input.setAttribute('autocapitalize', 'none');
  input.setAttribute('autocomplete', 'username');
  input.placeholder = 'irumaithy أو name@example.com';
  passwordInput.setAttribute('autocomplete', 'current-password');

  let resendBtn = document.getElementById('resendConfirmBtn');
  if (!resendBtn) {
    resendBtn = document.createElement('button');
    resendBtn.id = 'resendConfirmBtn';
    resendBtn.type = 'button';
    resendBtn.className = 'btn ghost hidden';
    resendBtn.style.cssText = 'width:100%;margin-top:10px';
    resendBtn.textContent = 'إعادة إرسال رابط تأكيد البريد';
    field?.parentElement?.after(resendBtn);
  }

  const authClient = window.supabase.createClient(
    cfg.SUPABASE_URL,
    cfg.SUPABASE_PUBLISHABLE_KEY,
    { auth: { persistSession: true, autoRefreshToken: true } }
  );

  const notify = (message) => {
    if (typeof window.toast === 'function') window.toast(message);
    else alert(message);
  };

  async function request(identifier, password = '', action = 'login') {
    const response = await fetch(`${cfg.SUPABASE_URL}/functions/v1/login-identifier`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': cfg.SUPABASE_PUBLISHABLE_KEY
      },
      body: JSON.stringify({ identifier, password, action })
    });
    let data = {};
    try { data = await response.json(); } catch (_) {}
    return { ok: response.ok && data?.ok, data, status: response.status };
  }

  loginBtn.onclick = async () => {
    const identifier = input.value.trim();
    const password = passwordInput.value;
    if (!identifier || !password) return notify('أدخل اسم المستخدم أو البريد وكلمة المرور');
    resendBtn.classList.add('hidden');
    loginBtn.disabled = true;
    try {
      const result = await request(identifier, password, 'login');
      if (!result.ok) {
        const code = result.data?.code;
        if (code === 'EMAIL_NOT_CONFIRMED') {
          resendBtn.classList.remove('hidden');
          return notify('البريد غير مؤكد. افتح رسالة التأكيد أو اضغط إعادة إرسال الرابط');
        }
        if (code === 'ACCOUNT_DISABLED') return notify('هذا الحساب موقوف من إدارة المنصة');
        if (code === 'RATE_LIMIT') return notify('محاولات كثيرة. حاول بعد قليل');
        if (code === 'SERVER_ERROR') return notify('تعذر الاتصال بخدمة الدخول الآن');
        return notify('اسم المستخدم/البريد أو كلمة المرور غير صحيحة');
      }

      const { error } = await authClient.auth.setSession({
        access_token: result.data.session.access_token,
        refresh_token: result.data.session.refresh_token
      });
      if (error) return notify('تعذر بدء جلسة الدخول');
      notify('تم تسجيل الدخول');
      const url = new URL(window.location.href);
      url.search = '?dashboard=1';
      url.hash = '';
      window.location.href = url.toString();
    } catch (error) {
      console.error(error);
      notify('تعذر الاتصال بخدمة الدخول');
    } finally {
      loginBtn.disabled = false;
    }
  };

  resendBtn.onclick = async () => {
    const identifier = input.value.trim();
    if (!identifier) return notify('أدخل اسم المستخدم أو البريد أولًا');
    resendBtn.disabled = true;
    try {
      const result = await request(identifier, '', 'resend');
      if (result.ok) return notify('تم إرسال رابط تأكيد جديد إلى بريدك');
      if (result.data?.code === 'RATE_LIMIT') return notify('تم الإرسال مؤخرًا. حاول بعد قليل');
      notify('تعذر إرسال رابط التأكيد');
    } catch (error) {
      console.error(error);
      notify('تعذر إرسال رابط التأكيد');
    } finally {
      resendBtn.disabled = false;
    }
  };
});
