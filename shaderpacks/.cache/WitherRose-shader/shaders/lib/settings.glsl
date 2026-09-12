#define COLORGRADING_EFFECT 3 // [0 1 2 3 4 5]
#define CELSHADE 1 // [1 0]
#define PIXEL 4 //[0 1 2 3 4]
#define MOTIONBLUR 1 // [0 1]

#if PIXEL <= 3
#define DotSize 0.1
#define Celradius 1
#elif PIXEL == 4
#define DotSize 3
#define Celradius 3
#endif