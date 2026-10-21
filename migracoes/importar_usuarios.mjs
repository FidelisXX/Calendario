// ============================================================
//  Importa os usuários de ibcj_users para o Supabase Auth + profiles
// ============================================================
//  Rodar DEPOIS da migração 01 e ANTES da migração 02.
//  Requer Node 18+ (usa fetch nativo, sem dependências).
//
//  PowerShell:
//    $env:SUPABASE_URL = "https://<projeto>.supabase.co"
//    $env:SUPABASE_SERVICE_ROLE_KEY = "<service_role key — Settings → API>"
//    $env:ADMIN_EMAIL = "<e-mail que hoje é o ADMIN_EMAIL do HTML>"
//    node migracoes/importar_usuarios.mjs --dry-run   # só mostra o que faria
//    node migracoes/importar_usuarios.mjs             # executa
//    node migracoes/importar_usuarios.mjs --pular=x@y.com,z@w.com   # ignora esses e-mails
//
//  A service_role key ignora todo o RLS: nunca coloque no HTML nem no git.
//
//  Idempotente: usuários que já existem no Auth são apenas re-vinculados.
//  Senhas com menos de 6 caracteres (mínimo do Supabase Auth) não são
//  importadas: o usuário é criado sem senha e precisa usar "Esqueci a senha".
// ============================================================

const URL_BASE = process.env.SUPABASE_URL?.replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || '').trim().toLowerCase();
const DRY = process.argv.includes('--dry-run');
// --pular=a@x.com,b@y.com → e-mails que não serão importados (ex.: cadastros duplicados/errados)
const PULAR = new Set((process.argv.find(a => a.startsWith('--pular=')) || '')
  .slice('--pular='.length).split(',').map(e => e.trim().toLowerCase()).filter(Boolean));
const MIN_PW = 6;

if (!URL_BASE || !KEY) {
  console.error('Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

// Chaves legadas são JWT: confere se é mesmo a service_role (erro comum: colar a anon)
if (KEY.startsWith('eyJ')) {
  let role;
  try { role = JSON.parse(Buffer.from(KEY.split('.')[1], 'base64url').toString()).role; } catch {}
  if (role !== 'service_role') {
    console.error(`Esta chave é "${role || 'inválida'}", não "service_role". Use a service_role (Settings → API Keys → Legacy API keys).`);
    process.exit(1);
  }
}

const headers = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };

async function api(method, path, body, extra = {}) {
  const res = await fetch(URL_BASE + path, { method, headers: { ...headers, ...extra }, body: body && JSON.stringify(body) });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${data?.msg || data?.message || text}`);
  return data;
}

async function listarUsuariosAuth() {
  const porEmail = new Map();
  for (let page = 1; ; page++) {
    const { users } = await api('GET', `/auth/v1/admin/users?page=${page}&per_page=1000`);
    users.forEach(u => porEmail.set(u.email.toLowerCase(), u));
    if (users.length < 1000) break;
  }
  return porEmail;
}

const [ibcj] = await api('GET', '/rest/v1/igrejas?tag=eq.ibcj&select=id');
if (!ibcj) {
  console.error('Igreja "ibcj" não encontrada — rode a migração 01 primeiro.');
  process.exit(1);
}

const legados = await api('GET', '/rest/v1/ibcj_users?select=id,name,email,pw,role&order=created_at');
const existentes = await listarUsuariosAuth();
const vistos = new Set();
const semSenha = [];
const falhas = [];
let criados = 0, vinculados = 0;

console.log(`${legados.length} usuários em ibcj_users${DRY ? ' (dry-run, nada será gravado)' : ''}\n`);

for (const u of legados) {
  const email = (u.email || '').trim().toLowerCase();
  if (!email) { falhas.push(`${u.id}: sem e-mail`); continue; }
  if (PULAR.has(email)) { console.log(`pular     ${email}`); continue; }
  if (vistos.has(email)) { falhas.push(`${email}: duplicado em ibcj_users (mantido o primeiro)`); continue; }
  vistos.add(email);

  let role = ['admin', 'pastor', 'secretaria', 'lider'].includes(u.role) ? u.role : 'lider';
  if (email === ADMIN_EMAIL) role = 'admin';
  const igreja_id = role === 'admin' || role === 'pastor' ? null : ibcj.id;
  const senhaOk = typeof u.pw === 'string' && u.pw.length >= MIN_PW;

  console.log(`${existentes.has(email) ? 'vincular' : 'criar   '}  ${email.padEnd(40)} ${role.padEnd(10)} ${igreja_id ? 'ibcj' : '(todas)'}${senhaOk ? '' : '  [sem senha]'}`);
  if (DRY) continue;

  try {
    let authUser = existentes.get(email);
    if (!authUser) {
      authUser = await api('POST', '/auth/v1/admin/users', {
        email,
        ...(senhaOk ? { password: u.pw } : {}),
        email_confirm: true,
        user_metadata: { name: u.name || '' },
      });
      criados++;
      if (!senhaOk) semSenha.push(email);
    } else {
      vinculados++;
    }
    // O trigger on_auth_user_created já criou o profile; aqui definimos papel e igreja.
    // Se o usuário existia no Auth antes da migração 01, o profile ainda não existe: cria.
    const perfil = { name: u.name || '', role, igreja_id, legacy_id: u.id };
    const atualizados = await api('PATCH', `/rest/v1/profiles?id=eq.${authUser.id}`, perfil,
      { Prefer: 'return=representation' });
    if (!atualizados.length) await api('POST', '/rest/v1/profiles', { id: authUser.id, email, ...perfil });
  } catch (e) {
    falhas.push(`${email}: ${e.message}`);
  }
}

console.log(`\nCriados: ${criados} | Já existiam (vinculados): ${vinculados} | Falhas: ${falhas.length}`);
if (semSenha.length) console.log(`\nCriados SEM senha (precisam usar "Esqueci a senha"):\n  ${semSenha.join('\n  ')}`);
if (falhas.length) { console.log(`\nFalhas:\n  ${falhas.join('\n  ')}`); process.exitCode = 1; }
