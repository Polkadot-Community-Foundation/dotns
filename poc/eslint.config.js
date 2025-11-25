import vue from 'eslint-plugin-vue';
import prettier from 'eslint-plugin-prettier';
import ts from '@typescript-eslint/eslint-plugin';
import parserTs from '@typescript-eslint/parser';
import vueParser from 'vue-eslint-parser';
import globals from 'globals';

export default [
  {
    ignores: ['dist', 'node_modules', '*.config.js'], 
  },
  {
    files: ['**/*.vue', '**/*.ts'],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: parserTs,
        ecmaVersion: 'latest',
        sourceType: 'module',
        extraFileExtensions: ['.vue'],
      },
      globals: {
        ...globals.browser,
        ...globals.node,
      },
    },
    plugins: {
      vue,
      prettier,
      '@typescript-eslint': ts,
    },
    rules: {
      'no-unused-vars': 'warn',
      '@typescript-eslint/no-unused-vars': ['warn'],
      'vue/multi-word-component-names': 'off',
      'prettier/prettier': 'warn',
    },
  },
];
