-- RIFA DA MESA DE SINUCA · 1000 números (000 a 999) a R$ 5
-- Sorteio pela Loteria Federal · reserva expira sozinha
-- Pode rodar mesmo que já tenha rodado versões anteriores.

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
alter table rifa_config add column if not exists prazo_horas      int  not null default 24;
alter table rifa_config add column if not exists loteria_concurso text;
alter table rifa_config add column if not exists loteria_premio   text;

create table if not exists rifa_numeros (
  numero        int primary key,
  status        text not null default 'livre' check (status in ('livre','reservado','pago')),
  nome          text,
  telefone      text,
  atualizado_em timestamptz default now()
);
alter table rifa_numeros add column if not exists reservado_em timestamptz;

create table if not exists rifa_admins (
  email text primary key
);

-- 2) Dados iniciais (números 000 a 999)
insert into rifa_config (id) values (1) on conflict do nothing;
update rifa_config set preco = 5, total = 1000, pix = 'kiqand21@gmail.com' where id = 1;  -- chave Pix (e-mail)
insert into rifa_numeros (numero) select generate_series(0, 999) on conflict do nothing;
delete from rifa_numeros where numero > 999 and status = 'livre';
update rifa_numeros set reservado_em = coalesce(atualizado_em, now()) where status = 'reservado' and reservado_em is null;
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

-- 5) Libera reservas não pagas depois do prazo (rifa_config.prazo_horas)
create or replace function rifa_liberar_vencidas() returns int
language plpgsql security definer set search_path = public as $$
declare qtd int;
begin
  update rifa_numeros
     set status = 'livre', nome = null, telefone = null, reservado_em = null, atualizado_em = now()
   where status = 'reservado'
     and reservado_em < now() - make_interval(hours => (select prazo_horas from rifa_config where id = 1));
  get diagnostics qtd = row_count;
  return qtd;
end $$;

-- 6) Público vê só os números ocupados (número + status, sem nome/telefone)
drop function if exists rifa_status();
create function rifa_status()
returns table (numero int, status text)
language plpgsql security definer set search_path = public as $$
begin
  perform rifa_liberar_vencidas();
  return query select r.numero, r.status from rifa_numeros r where r.status <> 'livre' order by r.numero;
end $$;

-- 7) Público reserva números livres (até 50 por vez)
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

  perform rifa_liberar_vencidas();
  perform 1 from rifa_numeros where numero = any (p_numeros) for update;
  select count(*) into livres from rifa_numeros where numero = any (p_numeros) and status = 'livre';
  if livres <> qtd then
    raise exception 'Algum desses números acabou de ser reservado. Atualize a página e escolha outro.';
  end if;

  update rifa_numeros
     set status = 'reservado', nome = trim(p_nome), telefone = trim(p_telefone),
         reservado_em = now(), atualizado_em = now()
   where numero = any (p_numeros);
end $$;

-- 8) Permissões
revoke all on function rifa_reservar(int[], text, text) from public;
revoke all on function rifa_liberar_vencidas()          from public;
grant execute on function rifa_status()                    to anon, authenticated;
grant execute on function rifa_reservar(int[], text, text) to anon, authenticated;
grant execute on function rifa_liberar_vencidas()          to authenticated;
grant execute on function rifa_is_admin()                  to authenticated;

-- 9) Ranking de maiores compradores (só números PAGOS; nome abreviado, sem telefone)
create or replace function rifa_ranking(p_limite int default 5)
returns table (nome text, qtd int)
language sql stable security definer set search_path = public as $$
  with p as (
    select coalesce(nullif(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), ''), lower(trim(nome))) as quem,
           regexp_split_to_array(trim(coalesce(nome, 'Anônimo')), '\s+') as partes
      from rifa_numeros
     where status = 'pago'
  ), g as (
    select quem, min(partes) as partes, count(*)::int as qtd from p group by quem
  )
  select initcap(partes[1]) ||
         case when array_length(partes, 1) > 1 then ' ' || upper(left(partes[array_length(partes, 1)], 1)) || '.' else '' end,
         qtd
    from g
   order by qtd desc, 1
   limit least(greatest(coalesce(p_limite, 5), 1), 20);
$$;
grant execute on function rifa_ranking(int) to anon, authenticated;
