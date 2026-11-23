#!/usr/bin/env nu

const anthropic_skills = [
  # algorithmic-art
  brand-guidelines
  # canvas-design
  claude-api
  # doc-coauthoring
  docx
  frontend-design
  # internal-comms
  mcp-builder
  pdf
  pptx
  skill-creator
  # slack-gif-creator
  # theme-factory
  web-artifacts-builder
  webapp-testing
  xlsx
]

const antithesis_skills = [
  antithesis-agent-browser
  antithesis-debug
  antithesis-documentation
  antithesis-launch
  antithesis-query-logs
  antithesis-research
  antithesis-setup
  antithesis-setup-k8s
  antithesis-skills-feedback
  antithesis-triage
  antithesis-workload
]

const matt_pocock_skills = [
  ask-matt
  code-review
  codebase-design
  diagnosing-bugs
  domain-modeling
  grill-me
  grill-with-docs
  grilling
  handoff
  implement
  implement-spec
  improve-codebase-architecture
  pr
  # prototype # Use Emil Kowalski's prototype instead; both share the same name.
  research
  retro
  setup-matt-pocock-skills
  tdd
  teach
  to-spec
  to-tickets
  to-questionnaire
  triage
  wait-what
  wayfinder
  wizard
  writing-for-agents

  # Optional: miscellaneous (uncomment to enable)
  # git-guardrails-claude-code
  # migrate-to-shoehorn
  # scaffold-exercises
  # setup-pre-commit

  # Optional: in-progress (uncomment to enable)
  # chief-of-staff
  # claude-handoff
  # loop-me
  # setup-ts-deep-modules
  # writing-beats
  # writing-fragments
  # writing-shape
]

const emil_kowalski_skills = [
  animate
  animate-expo
  animation-performance
  animation-vocabulary
  apple-design
  ask-sonner
  break-ui
  choreograph
  emil-design-eng
  find-animation-opportunities
  gestures
  improve-animations
  learn-taste
  mobile-native
  pick-ui-library
  prototype
  remove-animations
  review-animations
  write-swift
]

const nrminor_skills = [
  allocations
  back-of-envelope
  code-sketches
  codebase-searcher
  conceptual-pca
  effect-ts
  jj
  jj-preemptive-conflict-resolution
  local-ci
  logging
  performance-design
  self-doubt
  speak-in-code
]

def install-skills [source: string agent: string skills: list<string>] {
  ^nub dlx skills add $source --global --agent $agent --skill ...$skills --yes
}

install-skills "anthropics/skills" "opencode" $anthropic_skills
install-skills "antithesishq/antithesis-skills" "opencode" $antithesis_skills
install-skills "brianbell-x/codehygiene" "opencode" [codehygiene]
install-skills "dmmulroy/anti-slop" "opencode" [install-anti-slop]
install-skills "mattpocock/skills" "opencode" $matt_pocock_skills
install-skills "emilkowalski/skills" "opencode" $emil_kowalski_skills
install-skills "herdrdev/herdr" "opencode" [herdr]
install-skills "humanlayer/skills" "opencode" [show-me]
install-skills "snarktank/ralph" "opencode" [prd ralph]
install-skills "nrminor/skills" "opencode" $nrminor_skills
install-skills "pbakaus/impeccable" "opencode" [impeccable]
install-skills "uditgoenka/autoresearch" "opencode" [autoresearch]
