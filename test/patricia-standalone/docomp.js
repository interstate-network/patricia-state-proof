const path = require('path');
const compile = require('./compile');
const results = compile(__dirname, 'Test', path.join(__dirname, '..'));
const fs = require('fs');
fs.writeFileSync(path.join(__dirname, 'build', 'standard.json'), JSON.stringify(results, null, 2));