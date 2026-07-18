const formStorage = new LocalStorage();

@Entry(formStorage)
@Component
struct FreshCueCard {
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('card0Title') card0Title: string = '';
  @LocalStorageProp('card0Time') card0Time: string = '';
  @LocalStorageProp('card0Uri') card0Uri: string = 'freshcue://archive';
  @LocalStorageProp('card1Title') card1Title: string = '';
  @LocalStorageProp('card1Time') card1Time: string = '';
  @LocalStorageProp('card1Uri') card1Uri: string = 'freshcue://archive';
  @LocalStorageProp('card2Title') card2Title: string = '';
  @LocalStorageProp('card2Time') card2Time: string = '';
  @LocalStorageProp('card2Uri') card2Uri: string = 'freshcue://archive';
  @LocalStorageProp('card3Title') card3Title: string = '';
  @LocalStorageProp('card3Time') card3Time: string = '';
  @LocalStorageProp('card3Uri') card3Uri: string = 'freshcue://archive';

  @Builder
  cardRow(title: string, timeLabel: string, uri: string) {
    FormLink({ action: 'router', uri: uri }) {
      Row() {
        Column() {
          Text(title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18212F')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(timeLabel)
            .fontSize(11)
            .fontColor('#667085')
            .maxLines(1)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›')
          .fontSize(20)
          .fontColor('#667085')
      }
      .width('100%')
      .padding({ top: 7, bottom: 7 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('FreshCue')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3457D5')
        Blank()
        Text(`${this.count} 项待办`)
          .fontSize(11)
          .fontColor('#667085')
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.count === 0) {
        FormLink({ action: 'router', uri: 'freshcue://archive' }) {
          Column() {
            Text('暂无未完成卡片')
              .fontSize(15)
              .fontColor('#344054')
            Text('打开 FreshCue 导入截图')
              .fontSize(11)
              .fontColor('#667085')
              .margin({ top: 6 })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .layoutWeight(1)
        }
      } else {
        if (this.count > 0) {
          this.cardRow(this.card0Title, this.card0Time, this.card0Uri)
        }
        if (this.count > 1) {
          this.cardRow(this.card1Title, this.card1Time, this.card1Uri)
        }
        if (this.count > 2) {
          this.cardRow(this.card2Title, this.card2Time, this.card2Uri)
        }
        if (this.count > 3) {
          this.cardRow(this.card3Title, this.card3Time, this.card3Uri)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#F8FAFF')
  }
}
