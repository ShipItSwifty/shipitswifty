// A stand-in for Jest (the `jest` in its path is what makes ShipIt pass Jest's JSON flags) that writes what `jest --json --outputFile <path>` writes (absolute suite paths, one entry per
// test), so the fast fixture tier exercises ShipIt's Jest path without installing React Native.
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const flag = args.indexOf('--outputFile');
const titles = ['one', 'two', 'three', 'four', 'five'];
const result = {
  numFailedTestSuites: 0,
  numFailedTests: 0,
  numPassedTestSuites: 1,
  numPassedTests: titles.length,
  numPendingTestSuites: 0,
  numPendingTests: 0,
  numRuntimeErrorTestSuites: 0,
  numTotalTestSuites: 1,
  numTotalTests: titles.length,
  success: true,
  testResults: [
    {
      name: path.join(process.cwd(), '__tests__', 'sample.test.js'),
      status: 'passed',
      assertionResults: titles.map((title) => ({
        ancestorTitles: ['Sample'],
        failureMessages: [],
        fullName: `Sample ${title}`,
        status: 'passed',
        title,
      })),
    },
  ],
};
if (flag !== -1 && args[flag + 1]) {
  fs.writeFileSync(args[flag + 1], JSON.stringify(result));
}
console.log(`Tests: ${titles.length} passed, ${titles.length} total`);
