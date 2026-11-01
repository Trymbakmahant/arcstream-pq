import { useEffect, useRef } from 'react'

const vertexShaderSource = `
  attribute vec2 position;
  void main() {
    gl_Position = vec4(position, 0.0, 1.0);
  }
`

const fragmentShaderSource = `
  precision mediump float;
  uniform vec2 u_resolution;
  uniform float u_time;

  void main() {
    vec2 p = gl_FragCoord.xy / u_resolution.xy;
    p.x *= u_resolution.x / u_resolution.y;

    float t = u_time * 0.15;
    
    // Smooth sweeping waves based on sin/cos combinations
    float wave1 = sin(p.x * 2.0 + t) * 0.5 + 0.5;
    float wave2 = sin(p.y * 3.0 - t * 1.5 + wave1) * 0.5 + 0.5;
    float wave3 = sin((p.x + p.y) * 2.0 + t + wave2 * 2.0) * 0.5 + 0.5;
    
    // Soft Aurora Palette (brand lilac tones, dark background matching #080a0f)
    vec3 bg = vec3(0.031, 0.039, 0.059);
    vec3 auroraMain = vec3(0.894, 0.867, 0.941); // Lilac 400 #E4DDF0
    vec3 auroraSec = vec3(0.831, 0.796, 0.898); // Lilac 500 #D4CBE5 (primary brand)
    vec3 auroraAccent = vec3(0.612, 0.557, 0.722); // Lilac 700 #9C8EB8
    
    vec3 currentLayer = mix(auroraMain, auroraSec, wave1);
    currentLayer = mix(currentLayer, auroraAccent, wave2);
    
    // Mask out the aurora to just be glowing bands
    float mask = smoothstep(0.4, 0.6, wave3);
    mask *= sin(p.y * 3.14) * 1.2; // fade edges
    mask = clamp(mask, 0.0, 1.0);
    
    vec3 finalColor = mix(bg, currentLayer, mask * 0.4); // 0.4 opacity on glow
    
    // Add additive ambient light
    finalColor += auroraMain * smoothstep(0.7, 1.0, wave2) * 0.2;
    
    gl_FragColor = vec4(finalColor, 1.0);
  }
`

export function SoftAuroraBackground() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const gl = canvas.getContext('webgl', { alpha: false, antialias: false, powerPreference: 'low-power' })
    if (!gl) return

    const compileShader = (type: number, source: string): WebGLShader | null => {
      const shader = gl.createShader(type)
      if (!shader) return null
      gl.shaderSource(shader, source)
      gl.compileShader(shader)
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.warn('Shader compile failed:', gl.getShaderInfoLog(shader))
        gl.deleteShader(shader)
        return null
      }
      return shader
    }

    const vs = compileShader(gl.VERTEX_SHADER, vertexShaderSource)
    const fs = compileShader(gl.FRAGMENT_SHADER, fragmentShaderSource)
    if (!vs || !fs) return

    const program = gl.createProgram()
    if (!program) return
    gl.attachShader(program, vs)
    gl.attachShader(program, fs)
    gl.linkProgram(program)
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      console.warn('Program link failed:', gl.getProgramInfoLog(program))
      gl.deleteProgram(program)
      return
    }
    gl.useProgram(program)

    const vertices = new Float32Array([
      -1.0, -1.0,
       1.0, -1.0,
      -1.0,  1.0,
      -1.0,  1.0,
       1.0, -1.0,
       1.0,  1.0,
    ])

    const buffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW)

    const positionLocation = gl.getAttribLocation(program, 'position')
    gl.enableVertexAttribArray(positionLocation)
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0)

    const uTimeLocation = gl.getUniformLocation(program, 'u_time')
    const uResolutionLocation = gl.getUniformLocation(program, 'u_resolution')

    const resize = () => {
      if (!canvas || !canvas.parentElement) return
      const width = canvas.parentElement.clientWidth
      const height = canvas.parentElement.clientHeight
      const dpr = Math.min(window.devicePixelRatio || 1, 2)
      canvas.width = Math.floor(width * dpr)
      canvas.height = Math.floor(height * dpr)
      gl.viewport(0, 0, canvas.width, canvas.height)
      gl.uniform2f(uResolutionLocation, canvas.width, canvas.height)
    }

    window.addEventListener('resize', resize)
    resize()

    const startTime = Date.now()
    let animationFrameId: number

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    const render = () => {
      gl.uniform1f(uTimeLocation, (Date.now() - startTime) / 1000)
      gl.drawArrays(gl.TRIANGLES, 0, 6)
      if (!reduceMotion) animationFrameId = requestAnimationFrame(render)
    }
    render()

    return () => {
      window.removeEventListener('resize', resize)
      cancelAnimationFrame(animationFrameId)
      gl.deleteProgram(program)
      gl.deleteShader(vs)
      gl.deleteShader(fs)
      gl.deleteBuffer(buffer)
    }
  }, [])

  return (
    <div className="pointer-events-none absolute inset-0 z-0 overflow-hidden" aria-hidden="true">
      <canvas ref={canvasRef} className="absolute inset-0 size-full object-cover" />
      {/* Seamless vignette & bottom gradient to blend smoothly into the page canvas */}
      <div className="absolute inset-0 bg-gradient-to-b from-[#080a0f]/30 via-transparent to-[#080a0f]" />
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_30%,#080a0f_90%)] opacity-60" />
    </div>
  )
}
