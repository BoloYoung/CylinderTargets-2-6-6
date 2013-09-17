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

#ifndef CYLINDER_MODEL_H_
#define CYLINDER_MODEL_H_


// number of sides used to build the cylinder
#define CYLINDER_NB_SIDES 64

// 2 series of CYLINDER_NB_SIDES vertex, plus
// one for the bottom circle, one for the top circle
#define CYLINDER_NUM_VERTEX ((CYLINDER_NB_SIDES * 2) + 2)

#ifdef __cplusplus
extern "C" {
#endif

class CylinderModel {
public:
	CylinderModel(float topRadius);

	void* ptrVertices();
	void* ptrIndices();
	void* ptrTexCoords();
	void* ptrNormals();

	int nbIndices();

private:
	void prepareData();

	const float mTopRadius;

	float cylinderVertices[CYLINDER_NUM_VERTEX * 3];

	// 4 triangles per side, so 12 indices per side
	unsigned short cylinderIndices[CYLINDER_NB_SIDES * 12];

	float cylinderTexCoords[CYLINDER_NUM_VERTEX * 2];

	float cylinderNormals[CYLINDER_NUM_VERTEX * 3];

};

#ifdef __cplusplus
}
#endif
#endif // CYLINDER_MODEL_H_
