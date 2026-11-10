sub Main(args as Object)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.show()

    input = CreateObject("roInput")
    input.setMessagePort(port)

    scene.launchArgs = args
    scene.go = true

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" then
            if msg.isScreenClosed() then return
        else if type(msg) = "roInputEvent" then
            info = msg.getInfo()
            if info <> invalid then
                scene.launchArgs = info
                scene.go = true
            end if
        end if
    end while
end sub
