# Remotion video project

Make videos programmatically with React. Docs: <https://www.remotion.dev/docs>

## Commands

```sh
cd video
npm install

# Open the interactive Remotion Studio to preview and edit
npm run dev

# Render the HelloWorld composition to out/HelloWorld.mp4
npm run render

# Upgrade Remotion packages
npm run upgrade
```

## Structure

- `src/index.ts` — entry point, registers the root component
- `src/Root.tsx` — declares the compositions (id, duration, fps, dimensions)
- `src/HelloWorld.tsx` — an example animated composition
- `remotion.config.ts` — CLI configuration

Add a new video by creating a component and registering another
`<Composition>` in `src/Root.tsx`, then render it with
`npx remotion render <composition-id> out/<name>.mp4`.
