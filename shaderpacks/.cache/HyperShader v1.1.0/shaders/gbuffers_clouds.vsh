#version 120

/* gbuffers_clouds.vsh — Desactivamos las nubes planas vanilla para que solo
   se vean nuestras nubes procedurales (dibujadas en composite). */

void main() {
    gl_Position = ftransform();
}
