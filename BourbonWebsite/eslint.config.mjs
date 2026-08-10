import nextPlugin from "@next/eslint-plugin-next";
import nextParser from "eslint-config-next/parser";

const eslintConfig = [
  {
    ignores: [
      ".next/**",
      "node_modules/**",
      "coverage/**",
      "dist/**",
      "build/**",
      "next-env.d.ts"
    ]
  },
  {
    files: ["**/*.{js,jsx,mjs,ts,tsx,mts,cts}"],
    plugins: {
      "@next/next": nextPlugin
    },
    languageOptions: {
      parser: nextParser,
      parserOptions: {
        requireConfigFile: false,
        sourceType: "module",
        allowImportExportEverywhere: true,
        babelOptions: {
          parserOpts: {
            plugins: ["jsx", "typescript"]
          }
        }
      }
    },
    rules: nextPlugin.configs["core-web-vitals"].rules
  }
];

export default eslintConfig;
