package com.teachdian.vulcanic.ar

import android.opengl.GLES11Ext
import android.opengl.GLES20
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Draws the ARCore camera image as a full-screen quad.
 *
 * ARCore writes each camera frame into an external OES texture. The texture
 * coordinates come from ARCore too, because it knows how the sensor image
 * has to be cropped and rotated to fill the view.
 */
internal class CameraBackground {
    val textureId: Int
    private val program: Int
    private val positionAttribute: Int
    private val texCoordAttribute: Int
    private val quad: FloatBuffer = floatBuffer(
        floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f),
    )
    private val texCoords: FloatBuffer = floatBuffer(FloatArray(8))
    private var texCoordsReady = false

    init {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]
        val target = GLES11Ext.GL_TEXTURE_EXTERNAL_OES
        GLES20.glBindTexture(target, textureId)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)

        program = link(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttribute = GLES20.glGetAttribLocation(program, "a_Position")
        texCoordAttribute = GLES20.glGetAttribLocation(program, "a_TexCoord")
    }

    /** Forces the texture coordinates to be recomputed on the next draw. */
    fun invalidate() {
        texCoordsReady = false
    }

    fun draw(frame: Frame) {
        if (!texCoordsReady || frame.hasDisplayGeometryChanged()) {
            quad.position(0)
            texCoords.position(0)
            frame.transformCoordinates2d(
                Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                quad,
                Coordinates2d.TEXTURE_NORMALIZED,
                texCoords,
            )
            texCoordsReady = true
        }
        // No image has arrived yet; leave the cleared frame as it is.
        if (frame.timestamp == 0L) return

        quad.position(0)
        texCoords.position(0)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "u_Texture"), 0)
        GLES20.glVertexAttribPointer(positionAttribute, 2, GLES20.GL_FLOAT, false, 0, quad)
        GLES20.glVertexAttribPointer(texCoordAttribute, 2, GLES20.GL_FLOAT, false, 0, texCoords)
        GLES20.glEnableVertexAttribArray(positionAttribute)
        GLES20.glEnableVertexAttribArray(texCoordAttribute)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(positionAttribute)
        GLES20.glDisableVertexAttribArray(texCoordAttribute)
    }

    private fun link(vertexSource: String, fragmentSource: String): Int {
        fun compile(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            check(status[0] != 0) { "Shader failed: ${GLES20.glGetShaderInfoLog(shader)}" }
            return shader
        }
        val id = GLES20.glCreateProgram()
        GLES20.glAttachShader(id, compile(GLES20.GL_VERTEX_SHADER, vertexSource))
        GLES20.glAttachShader(id, compile(GLES20.GL_FRAGMENT_SHADER, fragmentSource))
        GLES20.glLinkProgram(id)
        val status = IntArray(1)
        GLES20.glGetProgramiv(id, GLES20.GL_LINK_STATUS, status, 0)
        check(status[0] != 0) { "Program failed: ${GLES20.glGetProgramInfoLog(id)}" }
        return id
    }

    private companion object {
        fun floatBuffer(values: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .apply {
                    put(values)
                    position(0)
                }

        const val VERTEX_SHADER = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = a_Position;
                v_TexCoord = a_TexCoord;
            }
        """

        const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            void main() {
                gl_FragColor = texture2D(u_Texture, v_TexCoord);
            }
        """
    }
}
