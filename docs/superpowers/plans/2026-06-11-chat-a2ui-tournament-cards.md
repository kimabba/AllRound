# Chat A2UI Tournament Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 챗봇이 대회 검색에 응답할 때 구조화된 대회 카드를 채팅 안에 렌더하고, 카드 액션으로 같은 채팅에서 후속 질문(`selected_entity`)을 이어갈 수 있게 한다.

**Architecture:** 기존 `tournament_search` 라우팅 경로(이미 `tournament_search_by_slots` RPC로 동작)에 새 SSE `ui` 이벤트를 추가해 대회 카드 items를 전송한다. 카드 빌더와 `selected_entity` 검증은 순수 함수로 분리해 deno로 테스트한다. Flutter는 `ui` 이벤트를 타입 안전 모델로 파싱해 메시지 버블 하단에 카드를 렌더하고, 카드 버튼은 `selected_entity`를 포함한 후속 chat 요청을 보낸다. 모든 권한 판정(visibility/eligibility)은 서버가 담당하고, 클라는 서버가 승인한 카드만 렌더한다.

**Tech Stack:** Deno (Supabase Edge Functions), TypeScript, Flutter/Dart, Riverpod, flutter_markdown, deno std assert, flutter_test.

**Scope (MVP):** 대회(tournament) 카드만. 클럽 카드/클럽 검색 RPC는 후속 계획. 상세화면 이동·신청 제출은 out of scope (스펙 "Out Of Scope").

---

## File Structure

**Backend (new/modified):**
- Create: `supabase/functions/_shared/chat_cards.ts` — 카드 아이템 타입 + 빌더 + `selected_entity` 검증 (순수 함수, 테스트 대상)
- Create: `supabase/functions/tests/chat_cards_test.ts` — chat_cards 순수 함수 테스트
- Modify: `supabase/functions/chat/index.ts` — `ChatBody`에 `selected_entity` 추가, tournament 라우팅에서 `send('ui', ...)`, selected_entity 검증/컨텍스트 주입

**Frontend (new/modified):**
- Create: `app/lib/models/chat_ui.dart` — `ChatUiBlock`, `TournamentChatCardItem`, `SelectedEntity` 타입 + fromJson
- Create: `app/lib/widgets/chat_tournament_card.dart` — `ChatTournamentCard` 위젯
- Create: `app/test/chat_ui_test.dart` — 모델 파싱 + 위젯 렌더 테스트
- Modify: `app/lib/services/api.dart` — `chat()`에 `selectedEntity` 파라미터 + 본문 인코딩
- Modify: `app/lib/screens/chat_screen.dart` — `_Msg.uiBlocks`, `ui` case, `_MessageBubble` 카드 렌더, 카드 액션 follow-up

---

## Phase 1 — Backend

### Task 1: 카드 아이템 빌더 + selected_entity 검증 (순수 함수)

**Files:**
- Create: `supabase/functions/_shared/chat_cards.ts`
- Test: `supabase/functions/tests/chat_cards_test.ts`

`tournament_search_by_slots` 가 반환하는 `TournamentSearchRow`(chat/index.ts:139-150)와 동일한 입력 형태를 받아, UI 안전한 카드 아이템으로 변환한다. `selected_entity` 검증은 잘못된 타입/형식의 id를 거부한다(스펙 "Reject invalid entity types and malformed ids").

- [ ] **Step 1: Write the failing test**

`supabase/functions/tests/chat_cards_test.ts`:

```typescript
import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildTournamentCards,
  parseSelectedEntity,
  type TournamentCardRow,
} from '../_shared/chat_cards.ts';

const SAMPLE_ROW: TournamentCardRow = {
  id: '11111111-1111-1111-1111-111111111111',
  sport: 'tennis',
  title: '광주 생활체육 테니스 오픈',
  start_date: '2026-06-13',
  end_date: '2026-06-13',
  region: '광주',
  location: '진월국제테니스장',
  eligible_grades: ['gj_m_gold'],
  entry_fee: 30000,
  format: '복식',
};

Deno.test('buildTournamentCards maps rows to display-safe items', () => {
  const cards = buildTournamentCards([SAMPLE_ROW]);
  assertEquals(cards.length, 1);
  const c = cards[0];
  assertEquals(c.id, SAMPLE_ROW.id);
  assertEquals(c.title, '광주 생활체육 테니스 오픈');
  assertEquals(c.sport, 'tennis');
  assertEquals(c.region, '광주');
  assertEquals(c.entry_fee, 30000);
  // only_my_grade=true 경로의 결과이므로 eligible=true 로 표기
  assertEquals(c.eligible, true);
});

Deno.test('buildTournamentCards caps at 10 items', () => {
  const rows = Array.from({ length: 25 }, (_, i) => ({ ...SAMPLE_ROW, id: `id-${i}` }));
  const cards = buildTournamentCards(rows);
  assertEquals(cards.length, 10);
});

Deno.test('parseSelectedEntity accepts a valid tournament entity', () => {
  const result = parseSelectedEntity({
    type: 'tournament',
    id: '11111111-1111-1111-1111-111111111111',
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.value.type, 'tournament');
    assertEquals(result.value.id, '11111111-1111-1111-1111-111111111111');
  }
});

Deno.test('parseSelectedEntity rejects invalid entity type', () => {
  const result = parseSelectedEntity({ type: 'user', id: '11111111-1111-1111-1111-111111111111' });
  assert(!result.ok);
});

Deno.test('parseSelectedEntity rejects malformed id', () => {
  const result = parseSelectedEntity({ type: 'tournament', id: 'not-a-uuid' });
  assert(!result.ok);
});

Deno.test('parseSelectedEntity returns ok=false for null/undefined', () => {
  assert(!parseSelectedEntity(undefined).ok);
  assert(!parseSelectedEntity(null).ok);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/chat_cards_test.ts`
Expected: FAIL with module-not-found / `buildTournamentCards` not exported.

- [ ] **Step 3: Write minimal implementation**

`supabase/functions/_shared/chat_cards.ts`:

```typescript
// Chat a2ui 카드 빌더 + selected_entity 검증 (순수 함수, 테스트 대상).
// 권한 판정은 호출자(Edge Function)가 담당. 여기서는 표시-안전 변환과 형식 검증만 한다.

export interface TournamentCardRow {
  id: string;
  sport: 'tennis' | 'futsal';
  title: string;
  start_date: string;
  end_date: string | null;
  region: string | null;
  location: string | null;
  eligible_grades: string[];
  entry_fee: number | null;
  format: string | null;
}

export interface TournamentCardItem {
  id: string;
  title: string;
  sport: 'tennis' | 'futsal';
  region: string | null;
  location: string | null;
  start_date: string;
  end_date: string | null;
  eligible: boolean;
  eligible_grades: string[];
  entry_fee: number | null;
  format: string | null;
}

const MAX_CARDS = 10;

/// `tournament_search_by_slots`(only_my_grade=true) 결과를 카드 아이템으로 변환.
/// 그 RPC는 참가 가능한 대회만 반환하므로 eligible=true 로 표기한다.
export function buildTournamentCards(rows: TournamentCardRow[]): TournamentCardItem[] {
  return rows.slice(0, MAX_CARDS).map((r) => ({
    id: r.id,
    title: r.title,
    sport: r.sport,
    region: r.region,
    location: r.location,
    start_date: r.start_date,
    end_date: r.end_date,
    eligible: true,
    eligible_grades: r.eligible_grades ?? [],
    entry_fee: r.entry_fee,
    format: r.format,
  }));
}

export type SelectedEntityType = 'tournament' | 'club';

export interface SelectedEntity {
  type: SelectedEntityType;
  id: string;
}

export type ParseResult<T> = { ok: true; value: T } | { ok: false };

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VALID_ENTITY_TYPES: readonly SelectedEntityType[] = ['tournament', 'club'];

/// 신뢰할 수 없는 입력에서 selected_entity 를 검증한다.
/// 잘못된 타입이나 UUID 형식이 아닌 id 는 거부한다.
export function parseSelectedEntity(input: unknown): ParseResult<SelectedEntity> {
  if (input === null || typeof input !== 'object') return { ok: false };
  const obj = input as Record<string, unknown>;
  const type = obj.type;
  const id = obj.id;
  if (typeof type !== 'string' || typeof id !== 'string') return { ok: false };
  if (!VALID_ENTITY_TYPES.includes(type as SelectedEntityType)) return { ok: false };
  if (!UUID_RE.test(id)) return { ok: false };
  return { ok: true, value: { type: type as SelectedEntityType, id } };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/chat_cards_test.ts`
Expected: PASS (7 tests).

- [ ] **Step 5: Lint/format and commit**

```bash
cd supabase/functions && deno fmt _shared/chat_cards.ts tests/chat_cards_test.ts && deno lint --config deno.json _shared/chat_cards.ts tests/chat_cards_test.ts
cd ../.. && git add supabase/functions/_shared/chat_cards.ts supabase/functions/tests/chat_cards_test.ts
git commit -m "feat(chat): add a2ui tournament card builder and selected_entity validation"
```

---

### Task 2: tournament 라우팅에서 `ui` 이벤트 발송

**Files:**
- Modify: `supabase/functions/chat/index.ts:732-773` (tournament 라우팅 성공 분기)

기존 `route`/`context`/`delta`/`citation` 발송 직후에 카드 items를 담은 `ui` 이벤트를 추가한다. 카드가 0건이면 발송하지 않는다(스펙 "If search returns no cards, ... instead of rendering an empty card block" — 이 분기는 이미 `rows.length > 0` 가드 안이라 항상 ≥1).

- [ ] **Step 1: Add import at top of chat/index.ts**

기존 import 블록(파일 상단, 다른 `_shared` import들과 같은 위치)에 추가:

```typescript
import { buildTournamentCards } from '../_shared/chat_cards.ts';
```

- [ ] **Step 2: Send `ui` event in the routed branch**

`chat/index.ts:760` 의 `send('citation', { items: citations });` 바로 다음 줄에 추가:

```typescript
            send('ui', {
              blocks: [
                {
                  type: 'cards',
                  entity: 'tournament',
                  items: buildTournamentCards(typedRows),
                },
              ],
            });
```

- [ ] **Step 3: Type-check**

Run: `cd supabase/functions && deno check --config deno.json chat/index.ts`
Expected: PASS (no type errors).

- [ ] **Step 4: Manual smoke verification (documented, not automated)**

`tournament_search` 라우팅은 통합 환경(배포된 Edge Function + 실제 user JWT)에서만 end-to-end 검증 가능하다. deno 단위 테스트 범위 밖임을 커밋 메시지에 명시한다. 카드 빌더 자체는 Task 1에서 이미 단위 테스트됨.

- [ ] **Step 5: Commit**

```bash
cd .. && git add supabase/functions/chat/index.ts
git commit -m "feat(chat): emit ui card block on tournament_search routing"
```

---

### Task 3: `selected_entity` 파싱·검증 + tournament 컨텍스트 주입

**Files:**
- Modify: `supabase/functions/chat/index.ts` — `ChatBody` 인터페이스(파일 상단 타입 선언부), 요청 검증 블록(470-482), 라우팅 이후 selected_entity 처리

카드 액션이 보낸 `selected_entity`(tournament)를 검증하고, 해당 대회를 user 클라이언트(RLS 적용)로 재조회해 visibility를 보장한 뒤 컨텍스트로 주입한다. 보이지 않으면 안내 메시지로 종료한다(스펙 "If the entity is no longer visible, the assistant should say the information is no longer available").

- [ ] **Step 1: Extend ChatBody and import**

`chat/index.ts` 상단 import에 추가(Task 2에서 이미 buildTournamentCards import했다면 같은 줄로 합친다):

```typescript
import { buildTournamentCards, parseSelectedEntity } from '../_shared/chat_cards.ts';
```

`ChatBody` 인터페이스(현재 `{ message, conversation_id?, active_sport? }`)에 필드 추가:

```typescript
interface ChatBody {
  message: string;
  conversation_id?: string;
  active_sport?: string;
  selected_entity?: unknown;
}
```

- [ ] **Step 2: Parse and validate selected_entity after message validation**

`chat/index.ts:482` 의 `const clientActiveSport: string | undefined = body.active_sport;` 바로 다음에 추가:

```typescript
  // 카드 액션 후속 요청의 선택 엔티티. 잘못된 타입/형식은 무시(검증 실패 시 일반 흐름).
  const selectedEntityResult = parseSelectedEntity(body.selected_entity);
  const selectedEntity = selectedEntityResult.ok ? selectedEntityResult.value : null;
```

- [ ] **Step 3: Handle a visible tournament selected_entity before intent flow**

`chat/index.ts:524` 의 `send('meta', { conversation_id: conversationId });` 다음, 임베딩 블록(526) 이전에 추가:

```typescript
        // ---- 카드 액션 후속: selected_entity(tournament) 결정적 처리 ----
        // 클라가 보낸 id 는 신뢰하지 않는다. user 클라이언트(RLS)로 재조회해
        // 가시성을 보장한 뒤에만 상세 컨텍스트로 사용한다.
        if (selectedEntity?.type === 'tournament') {
          const { data: selRow } = await supabase
            .from('tournaments')
            .select(
              'id, sport, title, region, location, start_date, end_date, ' +
                'application_deadline, entry_fee, format, eligible_grades',
            )
            .eq('id', selectedEntity.id)
            .maybeSingle();

          if (!selRow) {
            send('context', { tournaments: [], rules: [] });
            send('delta', {
              text:
                '현재 매치업 DB에서 이 항목을 확인할 수 없습니다. ' +
                '정보가 변경되었거나 접근 권한이 없을 수 있습니다.',
            });
            send('done', {});
            controller.close();
            return;
          }
        }
```

> 주의: 이 MVP 스텝은 selected_entity 가 보이지 않을 때의 거부만 결정적으로 처리한다. 보이는 경우는 통과시켜 아래 기존 intent/RAG/LLM 흐름이 사용자의 후속 질문(`상세 알려줘` 등)에 답하게 둔다. 완전한 결정적 detail 응답(필드 직접 렌더)은 후속 작업으로 남긴다(스펙 "deterministic details ... before falling back to RAG or LLM").

- [ ] **Step 4: Type-check**

Run: `cd supabase/functions && deno check --config deno.json chat/index.ts`
Expected: PASS.

- [ ] **Step 5: Lint/format and commit**

```bash
cd supabase/functions && deno fmt chat/index.ts && deno lint --config deno.json chat/index.ts
cd .. && git add supabase/functions/chat/index.ts
git commit -m "feat(chat): validate selected_entity and gate invisible tournaments"
```

---

## Phase 2 — Flutter

### Task 4: Chat UI 모델 (`ChatUiBlock`, `TournamentChatCardItem`)

**Files:**
- Create: `app/lib/models/chat_ui.dart`
- Test: `app/test/chat_ui_test.dart`

서버 `ui` 이벤트의 `blocks` 배열을 타입 안전하게 파싱한다. 파싱 실패는 예외 대신 빈 리스트로 흡수한다(스펙 "If card UI parsing fails on Flutter, the markdown answer should still render").

- [ ] **Step 1: Write the failing test**

`app/test/chat_ui_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/models/chat_ui.dart';

void main() {
  group('ChatUiBlock.listFromEvent', () {
    test('parses a tournament cards block', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {
                'id': '11111111-1111-1111-1111-111111111111',
                'title': '광주 테니스 오픈',
                'sport': 'tennis',
                'region': '광주',
                'location': '진월국제테니스장',
                'start_date': '2026-06-13',
                'end_date': '2026-06-13',
                'eligible': true,
                'eligible_grades': ['gj_m_gold'],
                'entry_fee': 30000,
                'format': '복식',
              }
            ],
          }
        ],
      };
      final blocks = ChatUiBlock.listFromEvent(data);
      expect(blocks.length, 1);
      expect(blocks.first.entity, 'tournament');
      expect(blocks.first.tournamentItems.length, 1);
      final item = blocks.first.tournamentItems.first;
      expect(item.title, '광주 테니스 오픈');
      expect(item.region, '광주');
      expect(item.entryFee, 30000);
      expect(item.eligible, true);
    });

    test('returns empty list on malformed payload', () {
      expect(ChatUiBlock.listFromEvent({'blocks': 'oops'}), isEmpty);
      expect(ChatUiBlock.listFromEvent(const {}), isEmpty);
      expect(ChatUiBlock.listFromEvent({'blocks': [42]}), isEmpty);
    });

    test('skips items with missing required fields', () {
      final data = {
        'blocks': [
          {
            'type': 'cards',
            'entity': 'tournament',
            'items': [
              {'id': 'x', 'sport': 'tennis'}, // no title/start_date
            ],
          }
        ],
      };
      final blocks = ChatUiBlock.listFromEvent(data);
      expect(blocks.single.tournamentItems, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/chat_ui_test.dart`
Expected: FAIL — `chat_ui.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`app/lib/models/chat_ui.dart`:

```dart
/// 채팅 a2ui 카드 모델. 서버 `ui` SSE 이벤트의 blocks 를 타입 안전하게 파싱한다.
/// 파싱 실패는 예외 대신 빈 결과로 흡수해 마크다운 답변이 항상 렌더되도록 한다.

class TournamentChatCardItem {
  final String id;
  final String title;
  final String sport;
  final String? region;
  final String? location;
  final String startDate;
  final String? endDate;
  final bool eligible;
  final List<String> eligibleGrades;
  final int? entryFee;
  final String? format;

  const TournamentChatCardItem({
    required this.id,
    required this.title,
    required this.sport,
    required this.region,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.eligible,
    required this.eligibleGrades,
    required this.entryFee,
    required this.format,
  });

  /// 필수 필드(id, title, sport, start_date)가 없으면 null 을 반환해 호출자가 건너뛴다.
  static TournamentChatCardItem? tryFromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final title = j['title'];
    final sport = j['sport'];
    final startDate = j['start_date'];
    if (id is! String || title is! String || sport is! String || startDate is! String) {
      return null;
    }
    return TournamentChatCardItem(
      id: id,
      title: title,
      sport: sport,
      region: j['region'] as String?,
      location: j['location'] as String?,
      startDate: startDate,
      endDate: j['end_date'] as String?,
      eligible: (j['eligible'] as bool?) ?? false,
      eligibleGrades: (j['eligible_grades'] as List?)?.cast<String>() ?? const [],
      entryFee: j['entry_fee'] as int?,
      format: j['format'] as String?,
    );
  }
}

class ChatUiBlock {
  final String type; // 'cards'
  final String entity; // 'tournament' | 'club'
  final List<TournamentChatCardItem> tournamentItems;

  const ChatUiBlock({
    required this.type,
    required this.entity,
    required this.tournamentItems,
  });

  /// `ui` 이벤트 data 에서 blocks 리스트를 파싱. 어떤 형식 오류든 빈 리스트로 흡수.
  static List<ChatUiBlock> listFromEvent(Map<String, dynamic> data) {
    final raw = data['blocks'];
    if (raw is! List) return const [];
    final result = <ChatUiBlock>[];
    for (final b in raw) {
      if (b is! Map) continue;
      final block = b.cast<String, dynamic>();
      final entity = block['entity'];
      if (entity is! String) continue;
      final itemsRaw = block['items'];
      final tournamentItems = <TournamentChatCardItem>[];
      if (entity == 'tournament' && itemsRaw is List) {
        for (final it in itemsRaw) {
          if (it is! Map) continue;
          final parsed = TournamentChatCardItem.tryFromJson(it.cast<String, dynamic>());
          if (parsed != null) tournamentItems.add(parsed);
        }
      }
      result.add(ChatUiBlock(
        type: (block['type'] as String?) ?? 'cards',
        entity: entity,
        tournamentItems: tournamentItems,
      ));
    }
    return result;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/chat_ui_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd .. && git add app/lib/models/chat_ui.dart app/test/chat_ui_test.dart
git commit -m "feat(chat): add typed chat ui card models"
```

---

### Task 5: `ApiService.chat()` 에 `selectedEntity` 추가

**Files:**
- Modify: `app/lib/services/api.dart:551-568` (chat 시그니처 + 본문)

- [ ] **Step 1: Add parameter and body encoding**

`app/lib/services/api.dart:551` 의 chat 시그니처에 파라미터 추가:

```dart
  Stream<ChatStreamEvent> chat({
    required String message,
    String? conversationId,
    bool enableSearch = true,
    String? activeSport,
    Map<String, String>? selectedEntity,
  }) async* {
```

`request.body = jsonEncode({...})` 블록(563-568)을 다음으로 교체:

```dart
    request.body = jsonEncode({
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
      'enable_search': enableSearch,
      if (activeSport != null) 'active_sport': activeSport,
      if (selectedEntity != null) 'selected_entity': selectedEntity,
    });
```

- [ ] **Step 2: Analyze**

Run: `cd app && flutter analyze --no-pub lib/services/api.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
cd .. && git add app/lib/services/api.dart
git commit -m "feat(chat): pass selected_entity in chat request body"
```

---

### Task 6: `_Msg.uiBlocks` + `ui` 이벤트 처리

**Files:**
- Modify: `app/lib/screens/chat_screen.dart:10-17` (`_Msg`), `:62-84` (switch), import 추가

- [ ] **Step 1: Import the model**

`chat_screen.dart` 상단 import 블록에 추가:

```dart
import '../models/chat_ui.dart';
```

- [ ] **Step 2: Add uiBlocks field to _Msg**

`chat_screen.dart:10-17` 의 `_Msg` 를 교체:

```dart
class _Msg {
  final String role;
  String content;
  List<Map<String, dynamic>> citations;
  List<ChatUiBlock> uiBlocks;

  _Msg({required this.role, required this.content})
      : citations = <Map<String, dynamic>>[],
        uiBlocks = <ChatUiBlock>[];
}
```

- [ ] **Step 3: Handle `ui` event in the switch**

`chat_screen.dart:83` 의 `case 'error':` 블록 바로 앞에 새 case 추가:

```dart
          case 'ui':
            final blocks = ChatUiBlock.listFromEvent(evt.data);
            if (blocks.isNotEmpty) {
              setState(() {
                _messages[assistantIdx].uiBlocks = [
                  ..._messages[assistantIdx].uiBlocks,
                  ...blocks,
                ];
              });
              _scrollToBottom();
            }
```

- [ ] **Step 4: Analyze**

Run: `cd app && flutter analyze --no-pub lib/screens/chat_screen.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
cd .. && git add app/lib/screens/chat_screen.dart
git commit -m "feat(chat): attach ui card blocks to assistant messages"
```

---

### Task 7: `ChatTournamentCard` 위젯 + 렌더링

**Files:**
- Create: `app/lib/widgets/chat_tournament_card.dart`
- Test: `app/test/chat_ui_test.dart` (위젯 테스트 추가)
- Modify: `app/lib/screens/chat_screen.dart` (`_MessageBubble` 카드 렌더)

카드는 raw id 를 렌더하지 않는다(스펙 "must not render those ids"). `AppCard`/디자인 토큰을 재사용한다. 액션 버튼은 콜백을 통해 후속 질문을 보낸다.

- [ ] **Step 1: Write the failing widget test**

`app/test/chat_ui_test.dart` 의 `main()` 안, 기존 group 다음에 추가:

```dart
  group('ChatTournamentCard', () {
    testWidgets('renders title, region and an action; hides id', (tester) async {
      const item = TournamentChatCardItem(
        id: '11111111-1111-1111-1111-111111111111',
        title: '광주 테니스 오픈',
        sport: 'tennis',
        region: '광주',
        location: '진월국제테니스장',
        startDate: '2026-06-13',
        endDate: '2026-06-13',
        eligible: true,
        eligibleGrades: ['gj_m_gold'],
        entryFee: 30000,
        format: '복식',
      );
      String? sent;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatTournamentCard(
            item: item,
            onAction: (message, entityId) => sent = message,
          ),
        ),
      ));

      expect(find.text('광주 테니스 오픈'), findsOneWidget);
      expect(find.textContaining('광주'), findsWidgets);
      expect(find.textContaining('11111111'), findsNothing); // id 노출 금지

      await tester.tap(find.text('상세 알려줘'));
      await tester.pump();
      expect(sent, '상세 알려줘');
    });
  });
```

`chat_ui_test.dart` 상단 import에 추가:

```dart
import 'package:flutter/material.dart';
import 'package:matchup/widgets/chat_tournament_card.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/chat_ui_test.dart`
Expected: FAIL — `chat_tournament_card.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`app/lib/widgets/chat_tournament_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/chat_ui.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';

/// 채팅 안에 렌더되는 대회 카드. raw id 는 표시하지 않는다.
/// 액션 버튼은 (message, entityId) 콜백으로 후속 chat 요청을 위임한다.
class ChatTournamentCard extends StatelessWidget {
  final TournamentChatCardItem item;
  final void Function(String message, String entityId) onAction;

  const ChatTournamentCard({
    super.key,
    required this.item,
    required this.onAction,
  });

  static const _actions = ['상세 알려줘', '신청 방법 알려줘', '마감 확인해줘'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = item.sport == 'tennis';
    final accent = isTennis ? cs.tertiary : cs.secondary;

    final meta = <String>[
      sportLabelFromString(item.sport),
      if (item.region != null) item.region!,
      item.endDate != null && item.endDate != item.startDate
          ? '${item.startDate} ~ ${item.endDate}'
          : item.startDate,
      if (item.entryFee != null) '${item.entryFee}원',
      if (item.format != null) item.format!,
    ].join(' · ');

    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTennis ? Icons.sports_tennis_rounded : Icons.sports_soccer_rounded,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.title,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            meta,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final action in _actions)
                OutlinedButton(
                  onPressed: () => onAction(action, item.id),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                  ),
                  child: Text(action, style: tt.labelMedium),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

> 검증: `sportLabelFromString` 가 `app/lib/utils/grade_labels.dart` 에 존재함을 확인했다(favorites_screen.dart 에서 사용 중). 시그니처가 다르면 `app/lib/utils/grade_labels.dart` 를 열어 실제 함수명으로 교체한다.

- [ ] **Step 4: Render cards in _MessageBubble**

`chat_screen.dart` 의 `_MessageBubble` 에서 citations 렌더 블록(`if (msg.citations.isNotEmpty) ...[ ... ]`) **직후**에 추가:

```dart
          if (msg.uiBlocks.isNotEmpty)
            for (final block in msg.uiBlocks)
              for (final item in block.tournamentItems)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: ChatTournamentCard(
                    item: item,
                    onAction: onCardAction,
                  ),
                ),
```

`_MessageBubble` 에 콜백 필드를 추가한다. 클래스 선언(`class _MessageBubble extends StatelessWidget`)과 생성자를 다음으로 교체:

```dart
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.onCardAction});
  final _Msg msg;
  final void Function(String message, String entityId) onCardAction;
```

`chat_tournament_card.dart` import 를 `chat_screen.dart` 상단에 추가:

```dart
import '../widgets/chat_tournament_card.dart';
```

`_messages` ListView 의 `itemBuilder`(현재 `(_, i) => _MessageBubble(msg: _messages[i])`)를 교체:

```dart
        itemBuilder: (_, i) => _MessageBubble(
          msg: _messages[i],
          onCardAction: _sendWithEntity,
        ),
```

> `_sendWithEntity` 는 Task 8 에서 정의한다. 이 스텝에서 일시적으로 컴파일 오류가 나면 Task 8 까지 묶어 진행한다.

- [ ] **Step 5: Run widget test + analyze**

Run: `cd app && flutter test test/chat_ui_test.dart`
Expected: PASS (위젯 테스트 포함 4 tests). `_sendWithEntity` 미정의로 chat_screen 컴파일이 막히면 Task 8 적용 후 재실행.

- [ ] **Step 6: Commit (Task 8과 함께)**

Task 8 적용 후 한 번에 커밋한다.

---

### Task 8: 카드 액션 → `selected_entity` 후속 전송

**Files:**
- Modify: `app/lib/screens/chat_screen.dart` (`_sendWithEntity` 추가, `_send` 리팩터 재사용)

카드 버튼 탭 시, 선택한 대회 id 를 `selected_entity` 로 포함한 후속 chat 요청을 보낸다.

- [ ] **Step 1: Add _sendWithEntity method**

`chat_screen.dart` 의 `_send()` 메서드 다음에 추가:

```dart
  Future<void> _sendWithEntity(String message, String entityId) async {
    if (_busy) return;
    setState(() {
      _messages.add(_Msg(role: 'user', content: message));
      _messages.add(_Msg(role: 'assistant', content: ''));
      _busy = true;
    });
    _scrollToBottom();

    final assistantIdx = _messages.length - 1;
    final api = ref.read(apiProvider);

    try {
      await for (final evt in api.chat(
        message: message,
        conversationId: _conversationId,
        activeSport: ref.read(activeSportProvider),
        selectedEntity: {'type': 'tournament', 'id': entityId},
      )) {
        if (!mounted) return;
        switch (evt.event) {
          case 'meta':
            _conversationId = evt.data['conversation_id'] as String?;
          case 'delta':
            setState(() {
              _messages[assistantIdx].content += evt.data['text'] as String? ?? '';
            });
            _scrollToBottom();
          case 'citation':
            final items = (evt.data['items'] as List?) ?? const [];
            setState(() {
              _messages[assistantIdx].citations = [
                ..._messages[assistantIdx].citations,
                ...items.cast<Map<String, dynamic>>(),
              ];
            });
          case 'ui':
            final blocks = ChatUiBlock.listFromEvent(evt.data);
            if (blocks.isNotEmpty) {
              setState(() {
                _messages[assistantIdx].uiBlocks = [
                  ..._messages[assistantIdx].uiBlocks,
                  ...blocks,
                ];
              });
              _scrollToBottom();
            }
          case 'error':
            setState(() {
              _messages[assistantIdx].content +=
                  '\n\n[오류] ${_formatChatError(evt.data['message'])}';
            });
        }
      }
    } catch (e) {
      setState(() {
        _messages[assistantIdx].content += '\n\n[연결 실패] ${_formatChatError(e)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

> DRY 참고: `_send` 와 이벤트 처리 switch 가 중복된다. 구현 후 여유가 있으면 공통 스트림 처리부를 `_consume(Stream<ChatStreamEvent>, int assistantIdx)` 헬퍼로 추출해 두 메서드에서 재사용한다. MVP 동작에는 영향 없으므로 선택적.

- [ ] **Step 2: Analyze full app**

Run: `cd app && flutter analyze --no-pub`
Expected: No issues found.

- [ ] **Step 3: Run all Flutter tests**

Run: `cd app && flutter test`
Expected: PASS (기존 + chat_ui_test).

- [ ] **Step 4: Commit**

```bash
cd .. && git add app/lib/screens/chat_screen.dart app/lib/widgets/chat_tournament_card.dart app/test/chat_ui_test.dart
git commit -m "feat(chat): render tournament cards and send selected_entity follow-ups"
```

---

## Final Verification

- [ ] **Backend checks**

```bash
cd supabase/functions
deno fmt --check _shared/chat_cards.ts tests/chat_cards_test.ts chat/index.ts
deno lint --config deno.json _shared/chat_cards.ts tests/chat_cards_test.ts chat/index.ts
deno check --config deno.json chat/index.ts
deno test --config deno.json --allow-env --allow-read tests
```

- [ ] **Flutter checks**

```bash
cd app
flutter analyze
flutter test
```

- [ ] **Manual/integration (documented)**

배포 후 실제 채팅에서 "서울 테니스 대회 알려줘" → 카드 렌더 확인, 카드의 "상세 알려줘" 탭 → 후속 답변 확인, 보이지 않는 대회 id 후속 → 안내 메시지 확인. (라우팅·LLM 경로는 단위 테스트 범위 밖, 통합 환경에서 검증.)

---

## Out Of Scope (후속)

- 클럽 카드 + 클럽 검색 RPC (approved-only) → `club_search` 라우팅
- 완전 결정적 detail 응답(필드 직접 렌더, RAG/LLM 우회)
- 카드에서 상세화면 이동 / 신청·가입 제출
- `application_deadline` 카드 표시 (현재 `tournament_search_by_slots` 반환 컬럼에 없음 → RPC 확장 필요)
