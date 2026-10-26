-- RIFA DA MESA DE SINUCA · 1000 números a R$ 5
-- Pode rodar mesmo que já tenha rodado a versão anterior.

-- 1) Tabelas
create table if not exists rifa_config (
  id               int primary key default 1 check (id = 1),
  premio           text    not null default 'Mesa de sinuca',
  descricao        text    default '',
  preco            numeric not null default 5,
  total            int     not null default 1000,
  data_sorteio     date,
  whatsapp         text    default '',
  pix              text    default '',
  resultado_numero int,
  resultado_em     timestamptz
);

create table if not exists rifa_numeros (
  numero        int primary key,
  status        text not null default 'livre' check (status in ('livre','reservado','pago')),
  nome          text,
  telefone      text,
  atualizado_em timestamptz default now()
);

create table if not exists rifa_admins (
  email text primary key
);

-- 2) Dados iniciais
insert into rifa_config (id) values (1) on conflict do nothing;
update rifa_config set preco = 5, total = 1000 where id = 1;
delete from rifa_numeros where numero > 1000;
insert into rifa_numeros (numero) select generate_series(1, 1000) on conflict do nothing;
insert into rifa_admins (email) values ('jebrecho123@gmail.com') on conflict do nothing;  -- <<< seu e-mail de login

create index if not exists rifa_numeros_status_idx on rifa_numeros (status);

-- 3) Quem é organizador
create or replace function rifa_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rifa_admins where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

-- 4) Segurança (RLS)
alter table rifa_config  enable row level security;
alter table rifa_numeros enable row level security;
alter table rifa_admins  enable row level security;

drop policy if exists "config leitura publica" on rifa_config;
drop policy if exists "config admin altera"    on rifa_config;
drop policy if exists "numeros admin le"       on rifa_numeros;
drop policy if exists "numeros admin altera"   on rifa_numeros;

create policy "config leitura publica" on rifa_config for select using (true);
create policy "config admin altera"    on rifa_config for update using (rifa_is_admin()) with check (rifa_is_admin());
create policy "numeros admin le"       on rifa_numeros for select using (rifa_is_admin());
create policy "numeros admin altera"   on rifa_numeros for update using (rifa_is_admin()) with check (rifa_is_admin());

-- 5) Público vê só os números ocupados (número + status, sem nome/telefone)
drop function if exists rifa_status();
create function rifa_status()
returns table (numero int, status text)
language sql stable security definer set search_path = public as $$
  select r.numero, r.status from rifa_numeros r where r.status <> 'livre' order by r.numero;
$$;

-- 6) Público reserva números livres (até 50 por vez)
create or replace function rifa_reservar(p_numeros int[], p_nome text, p_telefone text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  qtd    int := coalesce(array_length(p_numeros, 1), 0);
  livres int;
begin
  if coalesce(trim(p_nome), '') = '' or length(p_nome) > 80 then
    raise exception 'Informe seu nome.';
  end if;
  if coalesce(trim(p_telefone), '') = '' or length(p_telefone) > 20 then
    raise exception 'Informe seu WhatsApp.';
  end if;
  if qtd < 1 or qtd > 50 then
    raise exception 'Escolha de 1 a 50 números por reserva.';
  end if;
  if exists (select 1 from rifa_config where resultado_numero is not null) then
    raise exception 'O sorteio já foi feito.';
  end if;

  perform 1 from rifa_numeros where numero = any (p_numeros) for update;
  select count(*) into livres from rifa_numeros where numero = any (p_numeros) and status = 'livre';
  if livres <> qtd then
    raise exception 'Algum desses números acabou de ser reservado. Atualize a página e escolha outro.';
  end if;

  update rifa_numeros
     set status = 'reservado', nome = trim(p_nome), telefone = trim(p_telefone), atualizado_em = now()
   where numero = any (p_numeros);
end $$;

-- 7) Permissões
revoke all on function rifa_reservar(int[], text, text) from public;
grant execute on function rifa_status()                    to anon, authenticated;
grant execute on function rifa_reservar(int[], text, text) to anon, authenticated;
grant execute on function rifa_is_admin()                  to authenticated;
