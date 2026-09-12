/* MakeUp - E-LITE shaders 5 - depth.glsl
Depth utilities.

Javier Garduño - GNU Lesser General Public License v3.0
*/

float ld(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}
