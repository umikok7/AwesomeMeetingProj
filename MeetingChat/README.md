## 会议聊天

![会议聊天大致流程图](./会议聊天大致流程图.png)

## 技术栈

gin gorm redis Lua mysql livekit swagger

## 实现细节

推拉结合的实现方式，整体上提供两个接口：
- 推消息：SendMessage
- 拉消息（支持双向拉取）：PullMessage

先说推消息：
1. 推消息的时候实现难点在于如何进行落库并且保证消息推送时候的顺序性与一致性，为了维护顺序性和
一致性，就要在数据库中维护一个在当前roomSID下从1开始严格单调递增并且连续的序列号Seq，
前端根据该序列号来维护消息顺序一致性，此处为了保证原子性，引入`Lua+Redis`，发一条消息携带唯一的
uuid，以此为基础原子化地递增seq。uuid对应seq用hash结构保证幂等，seq简单用string存即可。

2. 第二个需要注意的地方在于：推消息的时候消息的落库问题。此处由于上述维护Seq的需求需要引入Lua脚本，
因此选择先落redis，后续开一个工作协程（Worker Goroutine）来消费消息执行落库。

3. 第三个注意的点在于如何保证mysql能够安全地存入全量的数据，此处采取的方案是利用Cron定时器，通过
定时每天的凌晨三点钟去检查被标记的roomSID的消息落库情况，简单地通过redis与mysql的Seq差别来判定
消息是否落库完成即可。

接下来是拉消息：
1. 先从redis拉，redis没得就去mysql拉
2. 拉消息主要就是约定好和前端交互的JSON协议就好了，此处设计为通过minSeq和maxSeq来决定拉取消息的
区间，具体设计为：

    a. 首次进入房间的时候，MinSeq和MaxSeq都是0，会默认拉取房间最新Seq之前的limit条消息（limit为分页大小，可以后续重新约定）

    b. 如果minSeq为0，maxSeq大于0，那么会拉取maxSeq之前的limit条消息

    c. 如果maxSeq为0，minSeq大于0，则正常拉取minSeq之后的limit条消息

    d. 其余都是minSeq和maxSeq都正常给出的情况，直接根据需求进行范围查询返回

