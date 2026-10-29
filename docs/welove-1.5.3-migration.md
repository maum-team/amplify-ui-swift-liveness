# Welove 1.5.3 UI 연동

기준: upstream 태그 `1.5.3` (`063bcf7`). 배포 대상: `1.5.3-welove.0`.
이번 마이그레이션에서는 릴리스 태그를 생성하지 않습니다. 검토한 소스를 커밋하고
배포하기 전까지는 로컬 Swift 패키지 경로를 지정해 사용합니다.

## 역할과 책임

얼굴 감지·매칭, 얼굴 이탈 처리, 상태 머신, 카메라 캡처, 챌린지 타이밍,
영상 기록 종료, AWS 이벤트, 화면 밝기, 자동 잠금, 화면 방향 처리는 upstream이 담당합니다.
관련 파일은 `1.5.3` 원본 그대로 유지합니다. 여기에는 `Freshness`,
`FaceLivenessDetectionViewModel`과 확장 파일, `LivenessStateMachine`, `VideoChunker`,
`FaceStateMatching`, `Instructor`, `OvalView`, `LivenessPreviewGeometry`가 포함됩니다.

호스트 앱은 선택적으로 `FaceLivenessPresentationController`를 전달해 UI 상태와
upstream이 그리는 타원의 정규화된 좌표를 관찰합니다. 이 컨트롤러는 뷰 모델이나 서비스를
참조하지 않으며 검사 상태를 직접 변경하지 않습니다. 선택적으로 연결한
`FaceLivenessColorRenderer`가 Skia 준비 완료 응답을 받아 색상 표시 시작을 연결합니다.
동일한 UI 이벤트는 반복해서 전달하지 않습니다. 호스트 앱이 RN 가이드를 그릴 때는
카메라 뷰가 네이티브 가이드를 숨깁니다. Native 모드는 네이티브 색상 뷰를 사용합니다. RN 모드는 해당 뷰를 숨기고 Skia가 색상을 표시합니다.
색상 타이밍·AWS 이벤트·영상 종료는 두 모드 모두 원본 `Freshness` 경로를 사용합니다.

표시 컨트롤러를 전달하지 않으면 원본 SwiftUI 안내 문구, 컨트롤, 가이드, 테마,
취소 버튼 API를 사용합니다. 컨트롤러를 전달하면 RN이 안내 문구, 진행률, 가이드,
취소 버튼, 검증 오버레이를 렌더링합니다. 색상 렌더러를 함께 전달하면 Skia 색상도 사용합니다.
RN 준비 화면은 기존과 같이 AWS 세션을 생성하기 전에 표시합니다.

## 1.4.8 포크에서 제거한 동작

- 추가 매칭 조건인 `minimumFaceSizeRatio`.
- 색상 검사 중 얼굴을 놓쳤을 때 타원 매칭 단계로 돌아가는 커스텀 상태 전이.
- 별도 네이티브 색상 타이머. RN 색상 시퀀스·준비 응답은 UI 전용 연결로 제공하며,
  원본 `Freshness`가 색상 이벤트와 완료를 처리합니다.
- upstream의 그리기 이벤트보다 먼저 타원을 전달하는 커스텀 동작.
- upstream의 영상 기록 종료 처리를 우회하는 RN 전용 완료 경로.

색상 검사 중 얼굴을 놓쳐도 색상을 처음부터 재시작하지 않습니다. 검사 결과는 서비스가
촬영된 영상을 바탕으로 판단합니다. 완료 콜백의 성공은 촬영과 서비스 통신이 완료됐다는
뜻이며, 사용자가 인증을 통과했다는 의미는 아닙니다.

## Expo 연동

래퍼는 컨트롤러의 `positioning`, `freshness`, `verifying` 상태를
`onUiStateChange`로 전달합니다. RN 모드에서는 `onColorChallengeSequence`로
AWS의 RGB·순서·지속시간·스크롤 여부와 회차 ID를 한 번에 전달합니다.
Skia가 준비되면 같은 ID로 `acknowledgeColorChallengeReady`를 호출합니다.
이 응답은 해당 회차를 한 번만 시작하며, 취소되거나 이전 회차의 응답은 무시합니다.

iOS는 준비 응답 후 원본 `Freshness`를 시작합니다. `onColorChallengeStart`는 시작 알림,
`onColorChallengeComplete`는 원본 색상 재생의 완료 알림입니다.
색상 완료 후에는 원본 `handleFreshnessComplete`와 `finishVideo`가 그대로 실행됩니다.
얼굴 이탈 처리나 매칭 조건을 바꾸지 않습니다. Android의 기존 시퀀스 렌더러도 유지합니다.

시퀀스를 받은 RN 화면은 어두운 마스크를 숨기고 Skia 색상을 표시해야 합니다.
문구·버튼과 물결 전환 효과는 꾸밀 수 있지만 AWS 챌린지의 RGB 값·순서·지속시간은 변경하지 않습니다.
Skia의 UI 스레드 시간표와 네이티브 타이밍은 별개이므로 표시 시차가 없거나
confidence가 원본과 같다고 보장하지 않습니다. 실제 기기에서 지연과 검사 결과를 비교합니다.

## 검증

iOS 시뮬레이터에서 `FaceLivenessPresentationControllerTests`, `FaceLivenessColorRendererTests`를 포함한
upstream `FaceLiveness` 스킴의 테스트를 실행합니다. 이 패키지를 사용하는 모노레포에서는
Expo 모듈 테스트와 모듈·예제 앱의 TypeScript 검사를 실행합니다.
기존 얼굴 이탈, 최종 이벤트, 영상 처리 동시성 테스트는 그대로 유지합니다.

실기기에서는 Native와 RN 모드 각각에서 Light/No light 세션으로 다음 항목을 확인합니다.
정상 완료, 앱을 완전히 종료한 뒤 실행했을 때의 첫 촬영, 반복 촬영, 색상 검사 중 얼굴 이탈,
어두운 환경에서의 촬영, 취소 후 재진입, 백그라운드 전환, 화면 회전,
화면 밝기와 자동 잠금 설정 복원입니다. 백엔드 실행 상태와 confidence도 비교합니다.
