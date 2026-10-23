# Convierte realesr-general-x4v3 (SRVGGNetCompact) a Core ML con bloques fijos de TILE px.
# Pesos: https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth
# Probado con torch 2.7.0 y coremltools 9.0 (en un venv).
# Uso: python scripts/convert-upscale-model.py <pesos.pth> Resources/Models/RealESRGAN.mlpackage [tile]
# Si se cambia el tile, hay que cambiar también `Upscaler.tile`.
import sys

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


class SRVGGNetCompact(nn.Module):
    # Copia de realesrgan/archs/srvgg_arch.py (BSD-3)
    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=32, upscale=4):
        super().__init__()
        self.upscale = upscale
        self.body = nn.ModuleList()
        self.body.append(nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.append(nn.PReLU(num_parameters=num_feat))
        for _ in range(num_conv):
            self.body.append(nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.append(nn.PReLU(num_parameters=num_feat))
        self.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.upsampler = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = x
        for layer in self.body:
            out = layer(out)
        out = self.upsampler(out)
        return out + F.interpolate(x, scale_factor=self.upscale, mode="nearest")


class Clamped(nn.Module):
    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        return self.net(x).clamp(0, 1)


src, dst = sys.argv[1], sys.argv[2]
tile = int(sys.argv[3]) if len(sys.argv) > 3 else 256

state = torch.load(src, map_location="cpu", weights_only=True)
state = state.get("params_ema") or state.get("params") or state
net = SRVGGNetCompact()
net.load_state_dict(state, strict=True)
model = Clamped(net).eval()

example = torch.rand(1, 3, tile, tile)
traced = torch.jit.trace(model, example)
ref = model(example).detach().numpy()

ml = ct.convert(
    traced,
    inputs=[ct.TensorType(name="input", shape=example.shape, dtype=np.float16)],
    outputs=[ct.TensorType(name="output", dtype=np.float16)],
    minimum_deployment_target=ct.target.macOS13,
    compute_precision=ct.precision.FLOAT16,
)
ml.short_description = "Real-ESRGAN realesr-general-x4v3 (BSD-3, Xintao Wang). x4, bloques de %d px" % tile
ml.save(dst)

out = ml.predict({"input": example.numpy().astype(np.float16)})["output"]
print("salida", out.shape, "error máx. vs PyTorch:", float(np.abs(out.astype(np.float32) - ref).max()))
