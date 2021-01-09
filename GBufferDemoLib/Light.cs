﻿using Microsoft.Xna.Framework;
using System;
using System.Collections.Generic;
using System.Text;

namespace GBufferDemoLib
{
    public class Light
    {
        public Color Color { get; set; }
        public Vector3 Position { get; set; }
        public float Range { get; set; }
        public float Intensity { get; set; }
    }
}
