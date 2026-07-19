const formStorage = new LocalStorage();

// 品牌配色与应用内一致：纸色底、墨色正文、朱砂强调、状态色只表达时效。
const COLOR_BG = '#FFFBF6';
const COLOR_BRAND = '#E05A47';
const COLOR_INK = '#252422';
const COLOR_MUTED = '#77736E';
const COLOR_URGENT = '#C94335';

@Entry(formStorage)
@Component
struct FreshCueCard {
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('card0Title') card0Title: string = '';
  @LocalStorageProp('card0Time') card0Time: string = '';
  @LocalStorageProp('card0Urgent') card0Urgent: boolean = false;
  @LocalStorageProp('card0Uri') card0Uri: string = 'freshcue://home';
  @LocalStorageProp('card1Title') card1Title: string = '';
  @LocalStorageProp('card1Time') card1Time: string = '';
  @LocalStorageProp('card1Urgent') card1Urgent: boolean = false;
  @LocalStorageProp('card1Uri') card1Uri: string = 'freshcue://home';
  @LocalStorageProp('card2Title') card2Title: string = '';
  @LocalStorageProp('card2Time') card2Time: string = '';
  @LocalStorageProp('card2Urgent') card2Urgent: boolean = false;
  @LocalStorageProp('card2Uri') card2Uri: string = 'freshcue://home';

  @Builder
  cardRow(title: string, timeLabel: string, urgent: boolean, uri: string) {
    Row() {
        Circle({ width: 7, height: 7 })
          .fill(urgent ? COLOR_URGENT : COLOR_BRAND)
          .margin({ right: 8 })
        Column() {
          Text(title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(timeLabel)
            .fontSize(11)
            .fontColor(urgent ? COLOR_URGENT : COLOR_MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›')
          .fontSize(20)
          .fontColor(COLOR_MUTED)
      }
      .width('100%')
      .padding({ top: 7, bottom: 7 })
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'moduleName': 'entry',
        'bundleName': 'com.freshcue.app',
        'abilityName': 'EntryAbility',
        'params': { 'freshcue_route': uri },
      })
    })
  }

  build() {
    Column() {
      Row() {
        Text('截期')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_BRAND)
        Blank()
        Text(this.count === 0 ? '' : `${this.count} 条临期`)
          .fontSize(11)
          .fontColor(COLOR_MUTED)
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.count === 0) {
        Column() {
            Text('暂时没有要记的事')
              .fontSize(15)
              .fontColor(COLOR_INK)
            Text('点一下，拍张截图记时间')
              .fontSize(11)
              .fontColor(COLOR_MUTED)
              .margin({ top: 6 })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .layoutWeight(1)
        .onClick(() => {
          postCardAction(this, {
            'action': 'router',
            'moduleName': 'entry',
            'bundleName': 'com.freshcue.app',
            'abilityName': 'EntryAbility',
            'params': { 'freshcue_route': 'freshcue://home' },
          })
        })
      } else {
        if (this.count > 0) {
          this.cardRow(this.card0Title, this.card0Time, this.card0Urgent, this.card0Uri)
        }
        if (this.count > 1) {
          this.cardRow(this.card1Title, this.card1Time, this.card1Urgent, this.card1Uri)
        }
        if (this.count > 2) {
          this.cardRow(this.card2Title, this.card2Time, this.card2Urgent, this.card2Uri)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor(COLOR_BG)
  }
}
