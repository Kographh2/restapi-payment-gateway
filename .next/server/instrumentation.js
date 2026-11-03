"use strict";
/*
 * ATTENTION: An "eval-source-map" devtool has been used.
 * This devtool is neither made for production nor for readable output files.
 * It uses "eval()" calls to create a separate source file with attached SourceMaps in the browser devtools.
 * If you are trying to read the output file, select a different devtool (https://webpack.js.org/configuration/devtool/)
 * or disable the default devtool with "devtool: false".
 * If you are looking for production-ready output files, see mode: "production" (https://webpack.js.org/configuration/mode/).
 */
(() => {
var exports = {};
exports.id = "instrumentation";
exports.ids = ["instrumentation"];
exports.modules = {

/***/ "(instrument)/./src/instrumentation.ts":
/*!********************************!*\
  !*** ./src/instrumentation.ts ***!
  \********************************/
/***/ ((__unused_webpack_module, __webpack_exports__, __webpack_require__) => {

eval("__webpack_require__.r(__webpack_exports__);\n/* harmony export */ __webpack_require__.d(__webpack_exports__, {\n/* harmony export */   register: () => (/* binding */ register)\n/* harmony export */ });\n// Next runs register before serving requests, including direct Next/Docker starts.\nasync function register() {\n    if (true) {\n        const { config } = await Promise.all(/*! import() */[__webpack_require__.e(\"vendor-chunks/zod\"), __webpack_require__.e(\"_instrument_src_services_config_ts\")]).then(__webpack_require__.bind(__webpack_require__, /*! ./services/config */ \"(instrument)/./src/services/config.ts\"));\n        const c = config();\n        if (c.PAYMENT_ENV === 'production') console.warn('MANJI: official provider verification is not onboarded. Verified payments and dynamic QRIS remain unavailable.');\n    }\n}\n//# sourceURL=[module]\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiKGluc3RydW1lbnQpLy4vc3JjL2luc3RydW1lbnRhdGlvbi50cyIsIm1hcHBpbmdzIjoiOzs7O0FBQUEsbUZBQW1GO0FBQzVFLGVBQWVBO0lBQ3BCLElBQUlDLElBQXFDLEVBQUU7UUFDekMsTUFBTSxFQUFDRyxNQUFNLEVBQUMsR0FBRyxNQUFNLDJQQUEyQjtRQUNsRCxNQUFNQyxJQUFJRDtRQUNWLElBQUlDLEVBQUVDLFdBQVcsS0FBSyxjQUFjQyxRQUFRQyxJQUFJLENBQUM7SUFDbkQ7QUFDRiIsInNvdXJjZXMiOlsiRDpcXERvd25sb2Fkc1xcR29QYXlfUVJJU19HYXRld2F5X0NvZGV4X0JsdWVwcmludFxcZ29wYXktcXJpcy1nYXRld2F5LWNvZGV4XFx3ZWJcXHNyY1xcaW5zdHJ1bWVudGF0aW9uLnRzIl0sInNvdXJjZXNDb250ZW50IjpbIi8vIE5leHQgcnVucyByZWdpc3RlciBiZWZvcmUgc2VydmluZyByZXF1ZXN0cywgaW5jbHVkaW5nIGRpcmVjdCBOZXh0L0RvY2tlciBzdGFydHMuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcmVnaXN0ZXIoKSB7XG4gIGlmIChwcm9jZXNzLmVudi5ORVhUX1JVTlRJTUUgPT09ICdub2RlanMnKSB7XG4gICAgY29uc3Qge2NvbmZpZ30gPSBhd2FpdCBpbXBvcnQoJy4vc2VydmljZXMvY29uZmlnJyk7XG4gICAgY29uc3QgYyA9IGNvbmZpZygpO1xuICAgIGlmIChjLlBBWU1FTlRfRU5WID09PSAncHJvZHVjdGlvbicpIGNvbnNvbGUud2FybignTUFOSkk6IG9mZmljaWFsIHByb3ZpZGVyIHZlcmlmaWNhdGlvbiBpcyBub3Qgb25ib2FyZGVkLiBWZXJpZmllZCBwYXltZW50cyBhbmQgZHluYW1pYyBRUklTIHJlbWFpbiB1bmF2YWlsYWJsZS4nKTtcbiAgfVxufVxuIl0sIm5hbWVzIjpbInJlZ2lzdGVyIiwicHJvY2VzcyIsImVudiIsIk5FWFRfUlVOVElNRSIsImNvbmZpZyIsImMiLCJQQVlNRU5UX0VOViIsImNvbnNvbGUiLCJ3YXJuIl0sImlnbm9yZUxpc3QiOltdLCJzb3VyY2VSb290IjoiIn0=\n//# sourceURL=webpack-internal:///(instrument)/./src/instrumentation.ts\n");

/***/ }),

/***/ "node:path":
/*!****************************!*\
  !*** external "node:path" ***!
  \****************************/
/***/ ((module) => {

module.exports = require("node:path");

/***/ })

};
;

// load runtime
var __webpack_require__ = require("./webpack-runtime.js");
__webpack_require__.C(exports);
var __webpack_exec__ = (moduleId) => (__webpack_require__(__webpack_require__.s = moduleId))
var __webpack_exports__ = (__webpack_exec__("(instrument)/./src/instrumentation.ts"));
module.exports = __webpack_exports__;

})();