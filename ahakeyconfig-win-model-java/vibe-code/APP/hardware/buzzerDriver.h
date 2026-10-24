/*
 * buzzerDriver.h
 *
 *  Created on: Feb 22, 2019
 *      Author: lukasz
 */

#ifndef BUZZERDRIVER_H_
#define BUZZERDRIVER_H_

#include "CONFIG.h"

typedef struct
{
    uint16_t  music_play;
    uint32_t  note_sum;
    uint32_t  note_curr;
    uint32_t *notes; //
    uint32_t *durat; //

} music_state_s;
extern music_state_s music_state;
void                 buzzerDriverInit(void);
void                 buzzerSetNewFrequency(uint32_t newFreq);
void                 start_music(int x);
void                 buzzerStop(void);

void      music_ticks(void);
extern u8 music_volume;
#endif /* BUZZERDRIVER_H_ */
