import { assertStringIncludes } from 'std/assert/mod.ts';

// 사용자 제보 대회(source='user_submission')는 크롤 원문(crawl_documents)이 없어
// AI 요강 정형화 대상이 아니다. insert 시 format_status 를 지정하지 않으면 DB
// 기본값 'pending' 이 되어 claim RPC 의 exists(crawl_documents) 조건에 영구
// 탈락(고아 pending)한다 — 프로덕션 실측 11건. handler() 가 export 되지 않고
// Supabase 클라이언트 체인 전체를 모킹하기엔 과한 표면이라, 이 레포의 wiring
// test 관례(age_gate_wiring_test.ts 등)를 따라 소스에서 배선을 직접 검증한다.
async function source(relativePath: string): Promise<string> {
  return await Deno.readTextFile(new URL(relativePath, import.meta.url));
}

Deno.test('사용자 제보 대회는 insert 시 format_status=skipped 로 요강 정형화 큐에서 제외된다', async () => {
  const endpoint = await source('../tournaments-submit/index.ts');
  assertStringIncludes(endpoint, "format_status: 'skipped'");
});
