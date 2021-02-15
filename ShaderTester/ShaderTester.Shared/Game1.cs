using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;
using System;

namespace ShaderTester
{
    public class Game1 : Game
    {
        private GraphicsDeviceManager _graphics;
        private SpriteBatch spriteBatch;
        private SpriteFont font;
        private Texture2D image0;
        private Texture2D image1;
        private Texture2D image2;
        private Texture2D image3;
        private Texture2D image4;
        private Texture2D image5;
        private BasicEffect effect0;
        private Effect effect1;
        private Effect effect2;
        private Matrix world;
        private Matrix view;
        private Matrix projection;
        float t;

#if MOJO
        string DiffuseTextureParameterName = "texsampler+DiffuseTexture";
        string NormalMapParameterName = "normalMapSampler+NormalMap";
        string SpecularMapParameterName = "specularMapSampler+SpecularMap";
#else
        string DiffuseTextureParameterName = "DiffuseTexture";
        string NormalMapParameterName = "NormalMap";
        string SpecularMapParameterName = "SpecularMap";
#endif

        public Game1()
        {
            _graphics = new GraphicsDeviceManager(this);
            _graphics.GraphicsProfile = GraphicsProfile.HiDef;

            Content.RootDirectory = "Content";
            IsMouseVisible = true;
        }

        protected override void Initialize()
        {
            // TODO: Add your initialization logic here

            this._graphics.PreferredBackBufferWidth = 1920;
            this._graphics.PreferredBackBufferHeight = 1080;
            this._graphics.SynchronizeWithVerticalRetrace = false;
            this._graphics.ApplyChanges();

            base.Initialize();
        }

        protected override void LoadContent()
        {
            spriteBatch = new SpriteBatch(GraphicsDevice);

            font = Content.Load<SpriteFont>("GameFont");

            image0 = Content.Load<Texture2D>("painterly/enchant-blue-3");
            image1 = Content.Load<Texture2D>("painterly/fireball-red-3");
            image2 = Content.Load<Texture2D>("painterly/protect-sky-3");
            image3 = Content.Load<Texture2D>("painterly/heal-sky-3");
            image4 = Content.Load<Texture2D>("painterly/evil-eye-eerie-3");
            image5 = Content.Load<Texture2D>("painterly/enchant-orange-1");

            effect0 = new BasicEffect(GraphicsDevice);
            effect1 = this.Content.Load<Effect>("lighting-noshadows");
            effect2 = this.Content.Load<Effect>("lighting-noshadows-assignedregisters");
        }

        protected override void Update(GameTime gameTime)
        {
            if (GamePad.GetState(PlayerIndex.One).Buttons.Back == ButtonState.Pressed || Keyboard.GetState().IsKeyDown(Keys.Escape))
                Exit();

            t += (float)gameTime.ElapsedGameTime.TotalSeconds;

            base.Update(gameTime);
        }

        protected override void Draw(GameTime gameTime)
        {
            GraphicsDevice.Clear(Color.CornflowerBlue);

            Vector3 cameraLookat = new Vector3(0, 0, 0);

            world = Matrix.Identity;
            view = Matrix.CreateLookAt(cameraLookat + new Vector3(0, 0, 5), cameraLookat, new Vector3(0, 1, 0));
            projection = Matrix.CreateOrthographicOffCenter(new Rectangle(0, 0, Window.ClientBounds.Width, Window.ClientBounds.Height), 0, 50);

            DrawText(new Vector2(10, 0), "sword");
            DrawText(new Vector2(10, 500), "fireball");
            DrawText(new Vector2(300, 0), "shield (register assignments)");
            DrawText(new Vector2(300, 500), "heart (register assignments)");

            DrawTriangle(effect1, image0, new Vector3(10, 20, 0));
            SpriteBatchDrawWithEffect(effect1, image1, new Vector3(10, 520, 0));

            DrawTriangle(effect2, image2, new Vector3(300, 20, 0));
            SpriteBatchDrawWithEffect(effect2, image3, new Vector3(300, 520, 0));

            base.Draw(gameTime);
        }

        private void DrawText(Vector2 loc, string text)
        {
            spriteBatch.Begin();
            spriteBatch.DrawString(font, text, loc, Color.White);
            spriteBatch.End();
        }

        private void SpriteBatchDraw()
        {
            spriteBatch.Begin();
            spriteBatch.Draw(image0, new Vector2(10, 10), Color.White);
            spriteBatch.End();
        }

        private void DrawTriangle(Effect effect, Texture2D texture, Vector3 pt)
        {
            VertexPositionColorTexture[] verts = new VertexPositionColorTexture[4];

            verts[0] = new VertexPositionColorTexture { Position = pt + new Vector3(0, 0, 0), Color = Color.White, TextureCoordinate = new Vector2(0, 0) };
            verts[1] = new VertexPositionColorTexture { Position = pt + new Vector3(256, 0, 0), Color = Color.White, TextureCoordinate = new Vector2(1, 0) };
            verts[2] = new VertexPositionColorTexture { Position = pt + new Vector3(0, 256, 0), Color = Color.White, TextureCoordinate = new Vector2(0, 1) };
            verts[3] = new VertexPositionColorTexture { Position = pt + new Vector3(256, 256, 0), Color = Color.White, TextureCoordinate = new Vector2(1, 1) };

            effect.CurrentTechnique = effect.Techniques["RenderLightAndSpecular"];

            effect.Parameters["World"].SetValue(world);
            effect.Parameters["ViewProjection"].SetValue(view * projection);
            effect.Parameters["MasterColor"].SetValue(new Vector4(1, 1, 1, 1));
            effect.Parameters[DiffuseTextureParameterName].SetValue(texture);
            effect.Parameters[NormalMapParameterName].SetValue(image4);
            effect.Parameters[SpecularMapParameterName].SetValue(image5);
            effect.Parameters["LightCount"].SetValue(0);
            effect.Parameters["AmbientLightColor"].SetValue(new Color(255, 255, 255).ToVector3());
            effect.Parameters["GlowAmount"].SetValue(new Vector4());

            foreach (var pass in effect.CurrentTechnique.Passes)
            {
                pass.Apply();

                GraphicsDevice.DrawUserPrimitives(PrimitiveType.TriangleStrip, verts, 0, 2);
            }
        }

        private void SpriteBatchDrawWithEffect(Effect effect, Texture2D texture, Vector3 pt)
        {
            spriteBatch.Begin(effect: effect
#if CUSTOM_MONOGAME
                , effectTextureParameter: effect.Parameters[DiffuseTextureParameterName]
#endif
                );
            spriteBatch.Draw(texture, new Vector2(pt.X, pt.Y), Color.White);
            spriteBatch.End();
        }

    }
}
