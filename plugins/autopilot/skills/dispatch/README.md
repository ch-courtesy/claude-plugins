# dispatch

여러 SPEC 파일을 구현→리뷰→머지 단계로 넘기는 **모델 주도 오케스트레이터** 스킬의 진입점이다.

## 무엇

`depends_on` 의존성을 풀어 **준비된 SPEC마다 서브에이전트를 1개** 띄운다. 각 서브에이전트가 자기 컨텍스트에서 한 SPEC 의 전 생애(구현·리뷰·머지)를 소유하고, dispatch 는 의존성·동시성 상한·실패 격리만 총괄한다. SPEC 이 머지(=done)되면 그 의존자를 해제한다.

## 언제

파일로 존재하는 SPEC(하나 이상)을 실제 구현·머지 단계로 진행하고 싶을 때. SPEC 작성 단계(`spec`/`repair`)의 옵트인 핸드오프 대상이다.

## 호출

```
Skill(skill="dispatch", args="<subcommand> [<args>]")
```

서브커맨드: `start` · `list` · `status` · `driver` · `concurrency` · `stop` · `watch` · `sweep`.

## 더 보기

- 동작·모델·서브커맨드 계약: [`SKILL.md`](./SKILL.md) (단일 출처)
- 서브에이전트 절차 계약: [`references/subagent-prompt.md`](./references/subagent-prompt.md)
- 오케스트레이션 헬퍼: [`references/dispatch.sh`](./references/dispatch.sh)
