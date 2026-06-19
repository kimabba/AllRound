-- 069: club-posts storage 업로드 정책 강화 (P3, 코덱스 교차검증)
--
-- 문제: 058 의 club_posts_storage_insert 가 "클럽 멤버만 업로드" 주석과 달리
--   bucket_id + authenticated 만 검사 → 로그인한 누구나 임의 경로(남의 폴더 포함)에
--   업로드 가능했음.
--
-- 한계: storage path 에 club_id 가 없어 storage RLS 만으로 "클럽 멤버" 검증은 불가.
--   현실적 최선으로 owner-folder 제한({user_id}/...)을 추가해 임의 경로/타인 폴더
--   업로드를 차단한다(기존 delete 정책의 foldername[1]=auth.uid() 와 대칭).
--   업로드 후 club_posts.image_urls 연결은 게시글 INSERT RLS(클럽 멤버)가 통제.

begin;

drop policy if exists club_posts_storage_insert on storage.objects;
create policy club_posts_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'club-posts'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

commit;
