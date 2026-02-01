# Coding Standards

## Formatting

### Indentation
- Use 2 spaces for indentation
- Do not use tabs

### Semicolons
- Do not use semicolons
- Rely on automatic semicolon insertion (ASI)

### Multiline Statements
- Use trailing periods on multiline statements for clarity

Example:
```javascript
const result = someFunction().
  then(data => processData(data)).
  catch(error => handleError(error))
```
