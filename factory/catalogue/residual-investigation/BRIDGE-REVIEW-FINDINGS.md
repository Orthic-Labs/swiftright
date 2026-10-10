# Bridge v2 review receipt

Parent v1 review identified four production defects: extension module masked nominal module, duplicate USR sections overwrote prior trees, unknown demangle records were ignored, & controls mutated derived dictionaries.

v2 fixes each defect. Parser rejects duplicate USRs & non-node records. Owner extraction retains nominal & extension modules independently. Controls deep-copy raw compiler trees or raw SourceKit entities, then invoke `bridge_accepts` or `raw_entity_matches`.

Pinned replay: 206 raw entities & 206 unique expanded USRs. 173 rows satisfy exact lexical nominal module/full owner path. 33 SwiftUI rows remain held because v6 lexical target starts `SwiftUICore.` while compiler tree nominal module is `SwiftUI`; no alias claim is made. Immutable link input remains `sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec`.
