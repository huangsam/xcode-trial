# XCode Agentic Guidelines

## Behavioral tips

When prototyping with computer vision algorithms:
- Generate Swift analyzer classes using Vision framework APIs
- Implement performance optimizations and error handling
- Consider extracted features in the context of an AI/ML pipeline

When organizing code for Swift/Vision framework:
- Design modular analyzer architectures
- Optimize for readability and maintainability
- Use SPM for package reuse over creating things from scratch

When documenting code:
- Maintain technical specs and integration guides
- Document architectural decisions and trade-offs

## Overall architecture

```
Agent Analysis → Code Generation → Testing → Documentation → Integration
     ↓               ↓            ↓          ↓            ↓
Requirements → Implementation → Validation → Knowledge → Deployment
```

### Tool Usage in Agent Workflows
- **Feature Extraction**: Use JSON output for ML training data
- **Content Analysis**: Automate video categorization and tagging
- **Quality Assessment**: Detect corrupted or low-quality content
- **Similarity Search**: Build recommendation systems based on video characteristics
