-- New accounts see the guided setup once. Existing accounts keep their current experience.
begin;

alter table public.profiles add column onboarding_completed_at timestamptz;

update public.profiles
set onboarding_completed_at=now()
where onboarding_completed_at is null;

commit;
