/*==============================================================================
            Copyright (c) 2013 QUALCOMM Austria Research Center GmbH.
            All Rights Reserved.
            Qualcomm Confidential and Proprietary

This Vuforia(TM) sample application in source code form ("Sample Code") for the
Vuforia Software Development Kit and/or Vuforia Extension for Unity
(collectively, the "Vuforia SDK") may in all cases only be used in conjunction
with use of the Vuforia SDK, and is subject in all respects to all of the terms
and conditions of the Vuforia SDK License Agreement, which may be found at
https://developer.vuforia.com/legal/license.

By retaining or using the Sample Code in any manner, you confirm your agreement
to all the terms and conditions of the Vuforia SDK License Agreement.  If you do
not agree to all the terms and conditions of the Vuforia SDK License Agreement,
then you may not retain or use any of the Sample Code in any manner.
==============================================================================*/


#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <sys/time.h>

#import <QCAR/QCAR.h>
#import <QCAR/State.h>
#import <QCAR/Renderer.h>
#import <QCAR/TrackableResult.h>

#import "EAGLView.h"
#import "QCARControl.h"
#import "Texture.h"
#import "ShaderUtils.h"
#import "sphere.h"

#define MAKESTRING(x) #x
#import "Shaders/Shader.fsh"
#import "Shaders/Shader.vsh"


//******************************************************************************
// *** OpenGL ES thread safety ***
//
// OpenGL ES on iOS is not thread safe.  We ensure thread safety by following
// this procedure:
// 1) Create the OpenGL ES context on the main thread.
// 2) Start the QCAR camera, which causes QCAR to locate our EAGLView and start
//    the render thread.
// 3) QCAR calls our renderFrameQCAR method periodically on the render thread.
//    The first time this happens, the defaultFramebuffer does not exist, so it
//    is created with a call to createFramebuffer.  createFramebuffer is called
//    on the main thread in order to safely allocate the OpenGL ES storage,
//    which is shared with the drawable layer.  The render (background) thread
//    is blocked during the call to createFramebuffer, thus ensuring no
//    concurrent use of the OpenGL ES context.
//
//******************************************************************************


extern BOOL displayIsRetina;


namespace {
    // --- Data private to this unit ---

    // Texture filenames
    const char* textureFilenames[NUM_AUGMENTATION_TEXTURES] = {
        "TextureTransparent.png",
        "sphere.png",
    };

    enum tagAugmentationTextureIndex {
        CYLINDER_TEXTURE_INDEX,
        BALL_TEXTURE_INDEX
    };

    // --- Cylinder ---
    // Dimensions of the cylinder (as set in the TMS tool)
    const float kCylinderHeight = 95.0f;
    const float kCylinderTopDiameter = 65.0f;
    const float kCylinderBottomDiameter = 65.0f;

    // Ratio between top and bottom diameter, used to generate the cylinder
    // model
    const float kCylinderTopRadiusRatio = kCylinderTopDiameter / kCylinderBottomDiameter;

    // Model scale factor (scaled to fit the actual cylinder)
    const float kCylinderScaleX = kCylinderBottomDiameter / 2.0;
    const float kCylinderScaleY = kCylinderBottomDiameter / 2.0;
    const float kCylinderScaleZ = kCylinderHeight;


    // --- Soccer ball ---
    // Make the ball 1/3 of the height of the cylinder
    const float kRatioBallHeight = 1.0f;
    const float kRatioCylinderHeight = 3.0f;

    // Augmentation model scale factor
    const float kBallObjectScale = kCylinderHeight / (kRatioCylinderHeight * kRatioBallHeight);
}


@interface EAGLView (PrivateMethods)

- (void)initShaders;
- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;
- (void)animateObject:(QCAR::Matrix44F&) modelViewMatrix;
- (double)getCurrentTime;

@end


@implementation EAGLView

// You must implement this method, which ensures the view's underlying layer is
// of type CAEAGLLayer
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


//------------------------------------------------------------------------------
#pragma mark - Lifecycle

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        // Enable retina mode if available on this device
        if (YES == displayIsRetina) {
            [self setContentScaleFactor:2.0f];
        }
        
        // Load the augmentation textures
        for (int i = 0; i < NUM_AUGMENTATION_TEXTURES; ++i) {
            augmentationTexture[i] = [[Texture alloc] initWithImageFile:[NSString stringWithCString:textureFilenames[i] encoding:NSASCIIStringEncoding]];
        }

        // Create the OpenGL ES context
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        // The EAGLContext must be set for each thread that wishes to use it.
        // Set it the first time this method is called (on the main thread)
        if (context != [EAGLContext currentContext]) {
            [EAGLContext setCurrentContext:context];
        }
        
        // Generate the OpenGL ES texture and upload the texture data for use
        // when rendering the augmentation
        for (int i = 0; i < NUM_AUGMENTATION_TEXTURES; ++i) {
            GLuint textureID;
            glGenTextures(1, &textureID);
            [augmentationTexture[i] setTextureID:textureID];
            glBindTexture(GL_TEXTURE_2D, textureID);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, [augmentationTexture[i] width], [augmentationTexture[i] height], 0, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)[augmentationTexture[i] pngData]);
        }

        [self initShaders];
        
        // Set the QCAR initialisation flags (informs QCAR of the OpenGL ES
        // version)
        [[QCARControl getInstance] setQCARInitFlags:QCAR::GL_20];

        // Instantiate the cylinder model
        cylinderModel = new CylinderModel(kCylinderTopRadiusRatio);
    }
    
    return self;
}


- (void)dealloc
{
    delete cylinderModel;
    [self deleteFramebuffer];
    
    // Tear down context
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    [context release];

    for (int i = 0; i < NUM_AUGMENTATION_TEXTURES; ++i) {
        [augmentationTexture[i] release];
    }

    [super dealloc];
}


- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  The render loop has
    // been stopped, so we now make sure all OpenGL ES commands complete before
    // we (potentially) go into the background
    if (context) {
        [EAGLContext setCurrentContext:context];
        glFinish();
    }
}


- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Free easily
    // recreated OpenGL ES resources
    [self deleteFramebuffer];
    glFinish();
}


//------------------------------------------------------------------------------
#pragma mark - UIGLViewProtocol methods

// Draw the current frame using OpenGL
//
// This method is called by QCAR when it wishes to render the current frame to
// the screen.
//
// *** QCAR will call this method periodically on a background thread ***
- (void)renderFrameQCAR
{
    [self setFramebuffer];

    // Clear colour and depth buffers
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // Begin QCAR rendering for this frame, retrieving the tracking state
    QCAR::State state = QCAR::Renderer::getInstance().begin();

    // Render the video background
    QCAR::Renderer::getInstance().drawVideoBackground();

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    for (int i = 0; i < state.getNumTrackableResults(); ++i) {
        glUseProgram(shaderProgramID);

        // Enable vertex, normal and texture coordinate arrays
        glEnableVertexAttribArray(vertexHandle);
        glEnableVertexAttribArray(normalHandle);
        glEnableVertexAttribArray(textureCoordHandle);

        // Get the trackable
        const QCAR::TrackableResult* result = state.getTrackableResult(i);
        QCAR::Matrix44F modelViewProjection;

        // --- Cylinder augmentation ---
        // The cylinder's texture is a transparent image; we draw it to obscure
        // the soccer ball, rather than to actually render it to the screen
        QCAR::Matrix44F modelViewMatrix = QCAR::Tool::convertPose2GLMatrix(result->getPose());

        // Scale the model, then apply the projection matrix
        ShaderUtils::scalePoseMatrix(kCylinderScaleX, kCylinderScaleY, kCylinderScaleZ, &modelViewMatrix.data[0]);
        ShaderUtils::multiplyMatrix([[QCARControl getInstance] projectionMatrix].data, &modelViewMatrix.data[0], &modelViewProjection.data[0]);

        // Set the vertex attribute pointers
        glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)cylinderModel->ptrVertices());
        glVertexAttribPointer(normalHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)cylinderModel->ptrNormals());
        glVertexAttribPointer(textureCoordHandle, 2, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)cylinderModel->ptrTexCoords());

        // Set the active texture unit
        glActiveTexture(GL_TEXTURE0);
        glUniform1i(texSampler2DHandle, 0);

        // Bind the texture and draw the geometry
        glBindTexture(GL_TEXTURE_2D, [augmentationTexture[CYLINDER_TEXTURE_INDEX] textureID]);
        glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewProjection.data[0] );
        glDrawElements(GL_TRIANGLES, cylinderModel->nbIndices(), GL_UNSIGNED_SHORT, (const GLvoid*)cylinderModel->ptrIndices());
        // --- End of cylinder augmentation ---

        // --- Soccer ball augmentation ---
        modelViewMatrix = QCAR::Tool::convertPose2GLMatrix(result->getPose());

        // Calculate the position of the ball at the current time
        [self animateObject:modelViewMatrix];

        // Translate and scale the model, then apply the projection matrix
        ShaderUtils::translatePoseMatrix(1.0f * kCylinderTopDiameter, 0.0f, kBallObjectScale, &modelViewMatrix.data[0]);
        ShaderUtils::scalePoseMatrix(kBallObjectScale, kBallObjectScale, kBallObjectScale, &modelViewMatrix.data[0]);
        ShaderUtils::multiplyMatrix([[QCARControl getInstance] projectionMatrix].data, &modelViewMatrix.data[0], &modelViewProjection.data[0]);

        // Set the vertex attribute pointers
        glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)&sphereVerts[0]);
        glVertexAttribPointer(normalHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)&sphereNormals[0]);
        glVertexAttribPointer(textureCoordHandle, 2, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)&sphereTexCoords[0]);

        // Bind the texture and draw the geometry
        glBindTexture(GL_TEXTURE_2D, [augmentationTexture[BALL_TEXTURE_INDEX] textureID]);
        glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewProjection.data[0]);
        glDrawArrays(GL_TRIANGLES, 0, sphereNumVerts);
        // --- End of soccer ball augmentation ---

        // Check for GL error
        ShaderUtils::checkGlError("EAGLView renderFrameQCAR");

        glDisableVertexAttribArray(vertexHandle);
        glDisableVertexAttribArray(normalHandle);
        glDisableVertexAttribArray(textureCoordHandle);
    }

    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    
    // End QCAR rendering for this frame
    QCAR::Renderer::getInstance().end();
    
    [self presentFramebuffer];
}


//------------------------------------------------------------------------------
#pragma mark - Private methods

//------------------------------------------------------------------------------
#pragma mark - OpenGL ES management

- (void)initShaders
{
    shaderProgramID = ShaderUtils::createProgramFromBuffer(vertexShader, fragmentShader);

    if (0 < shaderProgramID) {
        vertexHandle = glGetAttribLocation(shaderProgramID, "vertexPosition");
        normalHandle = glGetAttribLocation(shaderProgramID, "vertexNormal");
        textureCoordHandle = glGetAttribLocation(shaderProgramID, "vertexTexCoord");
        mvpMatrixHandle = glGetUniformLocation(shaderProgramID, "modelViewProjectionMatrix");
        texSampler2DHandle  = glGetUniformLocation(shaderProgramID,"texSampler2D");
    }
    else {
        NSLog(@"Could not initialise augmentation shader");
    }
}


- (void)createFramebuffer
{
    if (context) {
        // Create default framebuffer object
        glGenFramebuffers(1, &defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        GLint framebufferWidth;
        GLint framebufferHeight;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    }
}


- (void)deleteFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
        if (defaultFramebuffer) {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
    }
}


- (void)setFramebuffer
{
    // The EAGLContext must be set for each thread that wishes to use it.  Set
    // it the first time this method is called (on the render thread)
    if (context != [EAGLContext currentContext]) {
        [EAGLContext setCurrentContext:context];
    }
    
    if (!defaultFramebuffer) {
        // Perform on the main thread to ensure safe memory allocation for the
        // shared buffer.  Block until the operation is complete to prevent
        // simultaneous access to the OpenGL context
        [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
}


- (BOOL)presentFramebuffer
{
    // setFramebuffer must have been called before presentFramebuffer, therefore
    // we know the context is valid and has been set for this (render) thread
    
    // Bind the colour render buffer and present it
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    
    return [context presentRenderbuffer:GL_RENDERBUFFER];
}


//------------------------------------------------------------------------------
#pragma mark - Augmentation animation

- (void)animateObject:(QCAR::Matrix44F&)modelViewMatrix
{
    static float rotateBowlAngle = 0.0f;
    static double prevTime = [self getCurrentTime];
    double time = [self getCurrentTime];             // Get real time difference
    float dt = (float)(time-prevTime);          // from frame to frame

    rotateBowlAngle += dt * 180.0f/3.1415f;     // Animate angle based on time

    ShaderUtils::rotatePoseMatrix(rotateBowlAngle, 0.0f, 0.0f, 1.0f, &modelViewMatrix.data[0]);

    prevTime = time;
}


- (double)getCurrentTime
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

@end
