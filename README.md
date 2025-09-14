# Hack the North 2025 - Voice AI Integration Tech Demo

A technical demonstration showcasing real-time voice AI integration in interactive 3D environments. This project explores innovative voice interaction technology by combining VAPI (Voice AI Platform) with Godot Engine to create dynamic, voice-responsive experiences.

## Project Overview

This tech demo demonstrates advanced voice interaction capabilities by integrating real-time AI assistants into a 3D game environment. The project showcases how voice AI can create adaptive, contextual interactions that respond to both user speech patterns and environmental triggers.

### Key Technical Demonstrations

- **Real-time Voice Integration**: Continuous voice streaming and recognition using VAPI WebSocket API
- **Dynamic AI Assistant System**: Five distinct AI assistants that switch based on user silence, progress, and proximity events
- **Context-Aware Voice Responses**: AI assistants that adapt based on environmental triggers and player actions
- **Advanced Audio Processing**: Seamless integration of voice AI with game audio systems
- **Proximity-Based Events**: Demonstration of spatial awareness triggering voice system changes
- **Progressive Interaction Complexity**: Escalating assistant personalities based on user interaction patterns

## Technology Stack

### Game Engine
- **Godot Engine 4.4**: Main game development platform
- **GDScript**: Primary scripting language for game logic

### Voice AI Integration
- **VAPI (Voice AI Platform)**: Real-time voice recognition and synthesis
- **WebSocket API**: Continuous bidirectional communication with voice services
- **PCM Audio Streaming**: High-quality audio format (pcm_s16le, 48kHz)

## Technical Demonstrations

### Voice AI Progression System

1. **Original Assistant**: Initial conversational AI baseline
2. **Stall Assistant 1**: Demonstrates silence-based trigger (15 seconds)
3. **Stall Assistant 2**: Secondary escalation for extended silence periods
4. **Progress Assistant**: Context-aware switching based on environmental interaction
5. **Eerie Assistant**: Proximity and visual field-based activation
6. **Fin Assistant**: Distance-triggered final demonstration with movement restriction

### Interactive Technology Showcase

- **Graffiti Cleaning**: Raycast-based interaction with real-time audio feedback
- **Environmental State Management**: Dynamic object visibility based on progress tracking
- **Spatial Awareness**: Field-of-view and distance-based event triggering
- **Movement Control**: Contextual input restriction during specific voice interactions

## Setup and Installation

### Prerequisites
- Godot Engine 4.4 or later
- VAPI API key and assistant IDs

### Controls
- **WASD**: Movement (disabled during final sequence)
- **Mouse**: Camera control
- **Space**: Jump (disabled during final sequence)
- **Left Mouse Button**: Interact/Clean graffiti
- **Shift**: Run (while moving forward)
- **Microphone**: Voice input (always active)

## Development and Contribution

## Technical Challenges Solved

### Voice AI Integration
- **Real-time Streaming**: Implemented continuous PCM audio streaming with proper buffering
- **WebSocket Management**: Robust connection handling with automatic reconnection
- **Latency Optimization**: Minimized delay between voice input and AI response

### Assistant Switching Logic
- **Complex State Management**: Hierarchical assistant system with protection flags
- **Timing Coordination**: Synchronized voice switches with environmental events
- **Conflict Resolution**: Prevention of simultaneous assistant activations

## License

This project was created for Hack the North 2025. Please respect the event's guidelines and any applicable open source licenses for third-party assets used.

## Acknowledgments

- Hack the North 2025 organizers and sponsors
- VAPI team for voice AI technology
- Godot Engine community for development resources
- Asset creators for 3D models and audio files