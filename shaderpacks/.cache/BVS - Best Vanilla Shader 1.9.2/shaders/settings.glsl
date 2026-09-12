#define BY 0                            // By LoLip_p           [0 1]

#define ANTI_ALIASING 1                 // Anti-Aliasing        [0 1]
#define BIT 1                 			// BIT         			[0 1]
#define PBR 0                 			// PBR         			[0 1]
#define SSR 0                 			// SSR         			[0 1]
#define WAVES 1                 		// WAVES         		[0 1]
#define SWAYING_FOLIAGE 1               // SWAYING_FOLIAGE		[0 1]
#define SOFT 1               			// SOFT		 			[1 2]

#define AO_SIZE	1						// [1 2 4 6 8 10]

#define CHUNK_ANIMATION	1				// [0 1]
#define PIXEL_SHADOW 0               	// PIXEL_SHADOW		 	[0 16 32 64]

#define DOF 0                           //[0 1]
#define DOF_STRENGTH 2.0                //[1.0 2.0 4.0 8.0 16.0 32.0]

#define FOG 1 						    //[0 1]
#define FOG_DISTANCE 7                  //[5 7 10 13 15 17 20]

#define AUTO_EXPOSURE 0                 //[0 1]
#define EXPOSURE 0.00                   //[-2.00 -1.75 -1.50 -1.25 -1.00 -0.75 -0.50 -0.25 0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00]
#define AUTO_EXPOSURE_RADIUS 0.7        //[0.002 0.04 0.18 0.35 0.7]
#define AUTO_EXPOSURE_SPEED 0.033       //[0.0033 0.01 0.033 0.1 0.33]
#define TONEMAP_WHITE 4.0               //[1.0 1.5 2.0 2.5 3.0 3.5 4.0 5.0]

#define SATURATION 1.10                 // Saturation            [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25]
#define CONTRAST 1.025                  // Contrast              [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.025 1.05 1.075 1.10]
#define BRIGHTNESS 0.00                 // Brightness            [-1.00 -0.95 -0.90 -0.85 -0.80 -0.75 -0.70 -0.65 -0.60 -0.55 -0.50 -0.45 -0.40 -0.35 -0.30 -0.25 -0.20 -0.15 -0.10 -0.05 0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

#define BLOOM 0                         // Bloom                 [0 1]
#define BLOOM_THRESHOLD 0.975           // Bloom Threshold       [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.935 0.95 1.00]
#define BLOOM_INTENSITY 3.00            // Bloom Intensity       [0.00 0.20 0.40 0.60 0.80 1.00 1.20 1.40 1.60 1.80 2.00 2.20 2.40 2.60 2.80 3.00 3.20 3.40 3.60 3.80 4.00]
#define BLUR_RADIUS 3                   // Bloom Blur Radius     [0 1 2 3 4 5 6 7 8 9 10]

#define MOTION_BLUR 1                   // Motion Blur           [0 1]
#define MOTION_BLURRING_STRENGTH 1.25   // Motion Blur Strength  [0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00]

#define SHADING 1                       // Shading               [0 1]
#define ENABLE_SHADOW 1                 // Shadow                [0 1]
#define CLASSIC_NIGHT 0                 // Classic Night         [0 1]
#define NEW_LIGHTING 1                  // New Lighting          [0 1]
#define LIGHT_ABSORPTION 0.70           // Light Absorption      [0.00 0.10 0.20 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define SHADOW_TRANSPARENCY 0.10        // Shadow Transparency   [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.935 0.95 1.00]

const float sunPathRotation = -30.0;    // Sun Angle             [-90.0 -75.0 -60.0 -45.0 -30.0 -15.0 0.0 15.0 30.0 45.0 60.0 75.0 90.0]
const float shadowDistance = 96.0;      //                       [64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0 768.0 1024.0]
const int shadowMapResolution = 1536;   //                       [512 768 1024 1536 2048 3072 4096 8192]

#define AO 1							//[0 1]
#define DEBUG 0							//[0 1]
#define SAMPLES 16						//[4 6 8 10 12 16 24 32]
#define INTENSITY 2.0					//[0.5 1.0 1.5 2.0 2.5 3.0]
#define SCALE 1.0						//[0.1 0.2 0.3 0.5 0.75 1.0 2.0 3.0 5.0]
#define SAMPLE_RAD 0.1					//[0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.45 0.5 0.75 1.0]
#define MAX_DISTANCE 2.0				//[0.5 0.75 1.0 1.5 2.0 2.5 3.0 3.5]

const float shadowDistanceRenderMul = 1.0;
const float ambientOcclusionLevel = 0.5;						//[0.0 0.25 0.5 0.75 1.0]