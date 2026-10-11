# Corrected seed Mac captures v1

Fresh Mac capture packet for seed `14577611000270672472`, owned namespace only.

Five corrected cases each contain 20 independent raw archives:

- `swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258`
- `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258`
- `swiftui.scroll-view.recipe.gate-seeded.ca4e13f820f5d258`
- `swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258`
- `swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258`

Sources, manifests, cases & recipes are copied under `inputs/` with exact raw hashes. Custom source is `sha256:00989672411aae376c52781205b826c3e4ae5d6acc52e501a0032996dadcc98d`; preference source is `sha256:ec6837aefba5cd1b0d550675cb2577030ebc96b61ee5f5ee75a9bd852ca92463`. Stack/padding/scroll sources are pinned in `input-pins.json`.

Execution used copied inputs, copied signed recorder & fresh AX client under internal `SwiftRightFactory` cache only. AX trust preflight passed without permission requests. Candidate status stays observational & unpromoted; scroll offscreen & custom external AX remain held where recorded.

Validate packet:

```sh
python3 verify.py .
python3 -m unittest discover -s . -p 'test_*.py' -v
```
